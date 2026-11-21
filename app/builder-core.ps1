$BuilderLab=$PSScriptRoot
$PackageRoot=Split-Path $BuilderLab
$BuilderDir=Join-Path $PackageRoot 'data'
$Store=$BuilderDir
$Lists=Join-Path $PackageRoot 'lists'
$BuilderDraft=Join-Path $BuilderDir 'draft.json'
$BuilderActive=Join-Path $BuilderDir 'active.json'
$BuilderOriginal=Join-Path $BuilderDir 'original.json'
$BuilderService='myzapret2'
$env:PATH="$PackageRoot\bin\runtime;$env:PATH"
$VpnLog='C:\ProgramData\VPNUS\service.log'
. "$BuilderLab/builder-catalog.ps1"
$SiteGroups=[ordered]@{};$BuilderProbeGroups=[ordered]@{}
foreach($g in $BuilderCatalog.Keys){$SiteGroups[$g]=[string[]]$BuilderCatalog[$g].Domains;$BuilderProbeGroups[$g]=[string[]]$BuilderCatalog[$g].Urls}
function BSave($value,[string]$path){$json=$value|ConvertTo-Json -Depth 12;[IO.File]::WriteAllText("$path.tmp",$json,[Text.UTF8Encoding]::new($false));Move-Item -LiteralPath "$path.tmp" -Destination $path -Force}
function BRead([string]$path){if(Test-Path -LiteralPath $path){Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json}}
function BHash([string]$text){$sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-','')}finally{$sha.Dispose()}}
function Vpn-Connected {return (BVpnState) -ne 'Off'}
function Get-Configs {Get-ChildItem "$PackageRoot/strategies" -Filter *.json|Sort-Object Name|ForEach-Object {$_.BaseName}}
function BCheckDonor([string]$name){if($name -notin @(Get-Configs)){throw "Unknown zapret2 strategy: $name"}}
function BRecipe([string]$name){BCheckDonor $name;return BRead "$PackageRoot/strategies/$name.json"}
function BNewModel([string]$name){BCheckDonor $name;return [pscustomobject]@{Name='Мой zapret2';Engine='winws2';BaseName=$name;BaseImage=$name;Selections=[ordered]@{};GameFilter=$false;IpsetLoaded=$false}}
function BInitialize {
    New-Item -ItemType Directory -Force $BuilderDir,"$PackageRoot/reports"|Out-Null
    foreach($g in $SiteGroups.Keys){[IO.File]::WriteAllLines("$Lists/site-$g.txt",[string[]]$SiteGroups[$g],[Text.UTF8Encoding]::new($false))}
    if(-not(Test-Path $BuilderDraft)){BSave (BNewModel '01-split') $BuilderDraft}
}
function BSelections($model){
    $map=[ordered]@{}
    if($model.Selections -is [Collections.IDictionary]){foreach($key in $model.Selections.Keys){$map[$key]=$model.Selections[$key]}}
    elseif($model.Selections){foreach($p in $model.Selections.PSObject.Properties){$map[$p.Name]=$p.Value}}
    foreach($key in $map.Keys){if(-not $SiteGroups.Contains($key)){throw "Unknown service: $key"}}
    return $map
}
function BBaseHash($model){
    $voiceSalt=if($model.DiscordVoiceMode -eq 'continuous-ttl4'){'|voice=continuous-ttl4'}else{''}
    $content=@(Get-Configs|ForEach-Object {Get-Content "$PackageRoot/strategies/$_.json" -Raw}) -join "`n"
    return BHash ('profiles-v2|'+$voiceSalt+$content+'|'+$model.BaseName+"|game=$([bool]$model.GameFilter)|ipset=$([bool]$model.IpsetLoaded)|local=$([bool]$model.LocalTlsProxy)|packet=$($model.PacketMethod)|ips=$($model.PacketIPs -join ',')")
}
function BWithDonor($model,[string]$group,[string]$donor){
    if($model.Engine -eq 'winws'){throw 'Выбран точный старый состав. Для доноров winws2 сначала смените базу либо верните предыдущий состав через меню.'}
    BCheckDonor $donor;if(-not $SiteGroups.Contains($group)){throw 'Unknown service'}
    $copy=$model|ConvertTo-Json -Depth 12|ConvertFrom-Json;$map=BSelections $copy
    $map[$group]=[pscustomobject]@{Config=$donor;Quic=$true};$copy.Selections=$map;return $copy
}
function BProfile($recipe,[string]$hosts,[string]$kind){
    if($kind -eq 'tls'){return @('--filter-tcp 443','--filter-l7 tls',('--hostlist "'+$hosts+'"'),'--out-range -d10','--payload tls_client_hello')+@($recipe.Tls)}
    if($kind -eq 'quic'){return @('--filter-udp 443','--filter-l7 quic',('--hostlist "'+$hosts+'"'),'--out-range -d10','--payload quic_initial',('--lua-desync fake:blob=quic_google:repeats='+$recipe.QuicRepeats))}
    return @('--filter-tcp 80','--filter-l7 http',('--hostlist "'+$hosts+'"'),'--out-range -d10','--payload http_req','--lua-desync multisplit:pos=method+2')
}
function BBuild($model){
    if($model.Engine -eq 'winws' -and $model.BaseName -in @('alt13-spotify','general-stock','alt13-saved','alt13-apex-test','alt13-apex-exclusions')){
        $bundle=Join-Path $PackageRoot 'legacy'
        $image=([IO.File]::ReadAllText("$bundle/$($model.BaseName).txt")).Replace('{LEGACY}',$bundle)
        if($model.BaseName -eq 'general-stock' -and $model.YouTubeAlt){
            $rule=& {
                . "$PackageRoot/legacy/zapret_tool/zapret_core.ps1"
                if($model.YouTubeAlt -notin @(Get-Configs)){throw 'Unknown YouTube ALT'}
                $profile=@((Get-Profiles $model.YouTubeAlt $false).Profiles | Where-Object {(Get-Class $_) -eq 'google'})
                if($profile.Count -ne 1){throw 'Expected one Google profile'}
                Conv-Profile $profile[0]
            }
            $rule=$rule -replace '--hostlist "[^"]*list-google\.txt"',('--hostlist "'+$Lists+'/site-youtube.txt"') 
            $at=$image.IndexOf(' --filter-')
            $image=$image.Insert($at,' '+$rule+' --new')
        }
        return $image
    }
    if($model.Engine -eq 'winws'){return BLegacyImage -StockDiscord:([bool]$model.LegacyDiscordStock)}
    if($model.Engine -ne 'winws2' -or [string]::IsNullOrWhiteSpace($model.Name)){throw 'A named winws2 model is required'}
    $base=BRecipe $model.BaseName;$map=BSelections $model
    $tcp=if($model.GameFilter){'80,443,1024-65535'}else{'80,443,2053,2083,2087,2096,8443'}
    $udp=if($model.GameFilter){'443,1024-65535'}else{'443,19294-19344,50000-50100'}
    $argsList=@(('"'+$PackageRoot+'\bin\winws2.exe"'),"--wf-tcp-out $tcp","--wf-udp-out $udp",('--lua-init "@'+$PackageRoot+'\lua\zapret-lib.lua"'),('--lua-init "@'+$PackageRoot+'\lua\zapret-antidpi.lua"'),('--blob "quic_google:@'+$PackageRoot+'\bin\quic_initial_www_google_com.bin"'))
    $argsList+=('--blob "discord_stock:@'+$PackageRoot+'/legacy/bin/ACTIVE_DISCORD_UDP.bin"')
    $argsList+=('--blob "google_stock_tls:@'+$PackageRoot+'/legacy/bin/tls_clienthello_www_google_com.bin"')
    $profiles=New-Object Collections.Generic.List[string]
    # Scoped profiles precede the general fallback, so a donor wins only for its service.
    foreach($g in $map.Keys){
        $e=$map[$g];$recipe=BRecipe $(if($e -is [string]){$e}else{$e.Config})
        $exceptions=@(foreach($other in $SiteGroups.Keys){if($other -ne $g){foreach($domain in $SiteGroups[$other]){foreach($parent in $SiteGroups[$g]){if($domain.EndsWith('.'+$parent)){$domain;break}}}}})
        foreach($kind in @('tls','quic','http')){
            $profile=(BProfile $recipe "$Lists/site-$g.txt" $kind) -join ' '
            if($exceptions.Count){$profile+=' --hostlist-exclude-domains '+(($exceptions|Sort-Object -Unique) -join ',')}
            $profiles.Add($profile)
        }
    }
    if(-not $map.Contains('youtube')){
        $profiles.Add(('--filter-tcp 443 --filter-l7 tls --hostlist "'+$Lists+'/site-youtube.txt" --payload tls_client_hello --lua-desync fake:blob=google_stock_tls:tcp_ts=-1000:repeats=8:ip_id=zero --lua-desync multisplit:pos=1:seqovl=681:seqovl_pattern=google_stock_tls:ip_id=zero'))
    }
    foreach($kind in @('tls','quic','http')){$profiles.Add(((BProfile $base "$Lists/general.txt" $kind) -join ' '))}
    $voice=if($map.Contains('discord')){BRecipe $map.discord.Config}else{$base}
    $profiles.Add(('--filter-udp 19294-19344,50000-50100 --filter-l7 discord,stun --payload stun,discord_ip_discovery --lua-desync fake:blob=discord_stock:repeats=6'))
    $profiles.Add(((@('--filter-tcp 2053,2083,2087,2096,8443','--filter-l7 tls','--hostlist-domains discord.media','--out-range -d10','--payload tls_client_hello')+@($voice.Tls)) -join ' '))
    if($model.IpsetLoaded){
        foreach($kind in @('tls','quic','http')){
            $profile=(BProfile $base "$Lists/general.txt" $kind) -join ' '
            $profile=$profile.Replace(('--hostlist "'+$Lists+'/general.txt"'),('--ipset "'+$Lists+'/game-ipset.txt"'))
            $profiles.Add($profile)
        }
    }
    if($model.GameFilter -and $model.IpsetLoaded){
        $profiles.Add(((@('--filter-tcp 1024-65535','--filter-l7 tls',('--ipset "'+$Lists+'/game-ipset.txt"'),'--out-range -d10','--payload tls_client_hello')+@($base.Tls)) -join ' '))
        $profiles.Add(('--filter-udp 1024-65535 --filter-l7 stun,discord,wireguard --ipset "'+$Lists+'/game-ipset.txt" --out-range -d4 --payload stun,discord_ip_discovery,wireguard_initiation,wireguard_cookie --lua-desync fake:blob=0x00000000000000000000000000000000:repeats=2'))
    }
    if($model.PacketMethod){
        $ips=@($model.PacketIPs|Select-Object -Unique)
        if(-not $ips.Count){throw 'Packet method requires explicit target IPs'}
        foreach($ip in $ips){if([Net.IPAddress]::Parse($ip).AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork){throw 'Packet method requires IPv4'}}
        $method=@(BFImages $ips[0]|Where-Object Name -eq $model.PacketMethod|Select-Object -First 1)
        if(-not $method.Count){throw 'Unknown packet method'}
        $body=$method[0].Image.Substring($method[0].Image.IndexOf('--filter-tcp '))
        $body=$body.Replace(('--ipset-ip '+$ips[0]+' '),('--ipset-ip '+($ips -join ',')+' '))
        $profiles.Insert(0,$body);$argsList+='--wf-tcp-in 443'
    }
    if($model.LocalTlsProxy){for($i=0;$i -lt $profiles.Count;$i++){if($profiles[$i] -match '^--filter-tcp '){$profiles[$i]+=' --hostlist-exclude-domains googlevideo.com'}}}
    $built=($argsList -join ' ')+' '+($profiles -join ' --new ')
    if($model.DiscordVoiceMode -eq 'continuous-ttl4'){return BVoiceContinuousImage $built}
    return $built
}
function BValidate([string]$image){
    $tokens=@([regex]::Matches($image,'(?:[^\s"]|"[^"]*")+')|ForEach-Object {$_.Value})
    New-Item -ItemType Directory -Force "$PackageRoot/reports/validation"|Out-Null
    $prefix=Join-Path "$PackageRoot/reports/validation" ('validate-'+[guid]::NewGuid().ToString('N'))
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$tokens[0].Trim('"');$check=if([IO.Path]::GetFileName($info.FileName) -eq 'winws.exe'){'--dry-run '}else{'--intercept=0 '};$info.Arguments=$check+(($tokens|Select-Object -Skip 1) -join ' ')
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $p=New-Object Diagnostics.Process;$p.StartInfo=$info
    try{
        [void]$p.Start();$stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
        if(-not $p.WaitForExit(20000)){$p.Kill();throw 'winws2 initialization timed out'}
        $code=$p.ExitCode;$output=$stdout.Result+"`n"+$stderr.Result
        [IO.File]::WriteAllText("$prefix.log",$output)
    }finally{$p.Dispose()}
    if($code -ne 0){throw ("Движок не принял конфигурацию: exit=$code`n"+$output)}
}

function BStopService([string]$name){
    $s=Get-Service $name -ErrorAction SilentlyContinue
    if($s -and $s.Status -ne 'Stopped'){
        if($s.Status -ne 'StopPending'){Stop-Service $name -Force -ErrorAction Stop}
        (Get-Service $name).WaitForStatus('Stopped',[TimeSpan]::FromSeconds(20))
    }
}
function BRunImage([string]$image){
    $image=ConvertTo-ZapretServiceCommand $image "$BuilderDir/service-configs"
    BStopService $BuilderService
    if(Get-Service $BuilderService -ErrorAction SilentlyContinue){Set-ZapretServiceCommand $BuilderService $image}
    else{New-Service -Name $BuilderService -DisplayName 'MyZapret' -BinaryPathName $image -StartupType Manual | Out-Null}
    BStartManagedService
}
function BSnapshot {
    $services=@()
    foreach($name in @('zapret','zapret2','zapret-custom',$BuilderService)){
        $s=Get-Service $name -ErrorAction SilentlyContinue
        if($s){$r=Get-ItemProperty "HKLM:/SYSTEM/CurrentControlSet/Services/$name";$services += [pscustomobject]@{Name=$name;Running=($s.Status -eq 'Running');Start=[int]$r.Start;Image=[string]$r.ImagePath}}
    }
    $tasks=@(Get-ScheduledTask | Where-Object {$_.TaskName -in @('zapret-auto-mode','zapret-vpn-switch','zapret-best-test')}|ForEach-Object {[pscustomobject]@{Name=$_.TaskName;Path=$_.TaskPath;Enabled=($_.State -ne 'Disabled');Running=($_.State -eq 'Running')}})
    return [pscustomobject]@{Services=$services;Tasks=$tasks}
}
function BPause($snapshot,[switch]$Permanent){
    foreach($task in $snapshot.Tasks){Disable-ScheduledTask -TaskName $task.Name -TaskPath $task.Path|Out-Null;if($task.Running){Stop-ScheduledTask -TaskName $task.Name -TaskPath $task.Path}}
    foreach($s in $snapshot.Services){BStopService $s.Name;if($Permanent -and $s.Name -ne $BuilderService){Set-Service $s.Name -StartupType Disabled}}
    for($wait=0;$wait -lt 20 -and (Get-Process winws,winws2 -ErrorAction SilentlyContinue);$wait++){Start-Sleep -Milliseconds 250}
    if(Get-Process winws,winws2 -ErrorAction SilentlyContinue){throw 'Another standalone winws process is running. Close it before switching ALT.'}
}
function BRestore($snapshot,[bool]$RemoveNewService=$false){
    BStopService $BuilderService
    foreach($s in $snapshot.Services){
        Set-ZapretServiceCommand $s.Name (ConvertTo-ZapretServiceCommand $s.Image "$BuilderDir/service-configs")
        $mode=switch([int]$s.Start){2{'Automatic'}3{'Manual'}4{'Disabled'}default{throw 'Unsupported startup mode'}}
        Set-Service $s.Name -StartupType $mode
    }
    if($RemoveNewService -and -not @($snapshot.Services|Where-Object {$_.Name -eq $BuilderService}).Count){
        if(Get-Service $BuilderService -ErrorAction SilentlyContinue){& sc.exe delete $BuilderService|Out-Null;if($LASTEXITCODE -ne 0){throw 'Could not delete temporary custom service'}}
    }
    foreach($s in $snapshot.Services){if($s.Running -and -not(Vpn-Connected)){if($s.Name -eq $BuilderService){BStartManagedService}else{Start-Service $s.Name}}}
    foreach($t in $snapshot.Tasks){if($t.Enabled){Enable-ScheduledTask -TaskName $t.Name -TaskPath $t.Path|Out-Null;if($t.Running){Start-ScheduledTask -TaskName $t.Name -TaskPath $t.Path}}}
}
function BFreeze([string]$image,[string]$directory){
    New-Item -ItemType Directory -Force "$directory/lists"|Out-Null
    $pattern='--(?:hostlist|ipset)(?:-exclude)?\s+(?:"([^"]+)"|(\S+))'
    $out=$image
    foreach($m in [regex]::Matches($image,$pattern)){
        $path=if($m.Groups[1].Success){$m.Groups[1].Value}else{$m.Groups[2].Value}
        if(-not(Test-Path -LiteralPath $path)){throw "Missing list: $path"}
        $target=Join-Path "$directory/lists" ((BHash $path).Substring(0,10)+'-'+(Split-Path $path -Leaf))
        Copy-Item -LiteralPath $path -Destination $target -Force
        $out=$out.Replace($path,$target)
    }
    [IO.File]::WriteAllText("$directory/command.txt",$out,[Text.UTF8Encoding]::new($false))
    return $out
}

. "$BuilderLab/video-probe.ps1"

. "$BuilderLab/vpn-follow.ps1"

. "$BuilderLab/focused-lib.ps1"

. "$BuilderLab/service-command.ps1"

. "$BuilderLab/verified-default.ps1"

. "$BuilderLab/discord-voice-lib.ps1"

. "$BuilderLab/legacy-preset.ps1"

. "$BuilderLab/driver-recovery.ps1"

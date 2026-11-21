$ErrorActionPreference='Stop'
. "$PSScriptRoot/builder-core.ps1"
BInitialize
$dir=Join-Path "$PackageRoot/reports" ('YouTube-Scoped-'+(Get-Date -Format yyyyMMdd-HHmmss))
[void][IO.Directory]::CreateDirectory($dir)
$state="$BuilderDir/youtube-scoped.json"
$guard=$null
$snapshot=$null
$mutex=[Threading.Mutex]::new($false,'Local\MyZapretYoutubeScoped')
if(-not $mutex.WaitOne(0)){$mutex.Dispose();return}
function ProbePage($url){
    $code=& { $ErrorActionPreference='Continue'; curl.exe -q -4 --noproxy '*' -sS -L --connect-timeout 4 --max-time 7 -o NUL -w '%{http_code}' $url 2>> "$dir/curl-errors.txt" }
    return ($LASTEXITCODE -eq 0 -and "$code" -match '^[23]')
}
try{
    BSave @{State='Waiting';Report=$dir;PID=$PID} $state
    $deadline=[datetime]::UtcNow.AddHours(2)
    while(Vpn-Connected){
        if([datetime]::UtcNow -gt $deadline){throw 'VPN не отключён за время ожидания'}
        Start-Sleep -Seconds 2
    }
    $guard=BControlLock 45000
    if(-not $guard -or (Vpn-Connected)){throw 'Служба занята или VPN снова включён'}
    $active=BRead $BuilderActive
    if($active.Model.BaseName -ne 'general-stock'){throw 'Выбран другой основной состав'}
    $alts=& {. "$PackageRoot/legacy/zapret_tool/zapret_core.ps1"; Get-Configs}
    $seen=@{}
    $snapshot=BSnapshot
    BPause $snapshot
    $winner=$null
    foreach($alt in @('')+$alts){
        if(Vpn-Connected){throw 'VPN снова включён'}
        $model=$active.Model|ConvertTo-Json -Depth 10|ConvertFrom-Json
        $model|Add-Member YouTubeAlt $alt -Force
        try{$image=BBuild $model}catch{continue}
        $hash=BHash $image
        if($seen.ContainsKey($hash)){continue}
        $seen[$hash]=$true
        BSave @{State='Running';Report=$dir;PID=$PID;Candidate=$alt} $state
        BRunImage $image
        $page=ProbePage 'https://www.youtube.com/'
        $media=$null
        $discord=$false
        if($page){
            $script:BVideoCache=$null
            $media=BVideoProbe $dir
            if($media.Pass){
                $discord=ProbePage 'https://discord.com/api/v10/gateway'
                $script:BVideoCache=$null
                if($discord -and (BVideoProbe $dir).Pass){$winner=$model}
            }
        }
        if(Vpn-Connected){throw 'VPN снова включён'}
        [pscustomobject]@{ALT=$alt;Page=$page;Video=[bool]$media.Pass;Discord=$discord;Confirmed=[bool]$winner;Details=$media.Details}|Export-Csv "$dir/results.csv" -Append -NoTypeInformation -Encoding UTF8
        if($winner){break}
    }
    BRestore $snapshot $true
    $snapshot=$null
    if($winner -and $winner.YouTubeAlt){
        if(Vpn-Connected){throw 'VPN снова включён перед применением'}
        $winner.Name='Обычный zapret + YouTube '+$winner.YouTubeAlt
        BInstallStoredPreset -Model $winner|Set-Content "$dir/applied.txt" -Encoding UTF8
    }
    BSave @{State='Complete';Report=$dir;Confirmed=[bool]$winner;Applied=$winner.YouTubeAlt} $state
}catch{
    BSave @{State='Failed';Report=$dir;Error=$_.Exception.Message} $state
}finally{
    try{if($snapshot){BRestore $snapshot $true}}finally{if($guard){$guard.Dispose()};[void]$mutex.ReleaseMutex();$mutex.Dispose()}
}
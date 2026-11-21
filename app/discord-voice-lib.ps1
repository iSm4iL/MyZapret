function BVoiceBypassImage([string]$Image){
    $parts=@($Image -split ' --new ');$changed=0
    for($i=0;$i -lt $parts.Count;$i++){
        if($parts[$i] -match '--filter-udp 19294-19344,50000-50100 --filter-l7 discord,stun'){
            if($parts[$i] -match 'fake:blob=discord_stock'){
                $parts[$i]=$parts[$i].Replace('--payload stun,discord_ip_discovery','--out-range x --payload stun,discord_ip_discovery')
                $changed++
                continue
            }
            if($parts[$i] -notmatch '--out-range -d4'){throw 'Unknown Discord UDP profile; automatic modification refused'}
            $parts[$i]=$parts[$i].Replace('--out-range -d4','--out-range x');$changed++
        }
    }
    if($changed -ne 1){throw 'Expected exactly one Discord voice UDP profile'}
    return $parts -join ' --new '
}
function BVoiceContinuousImage([string]$Image){
    $parts=@($Image -split ' --new ');$changed=0
    for($i=0;$i -lt $parts.Count;$i++){
        if($parts[$i] -match '--filter-udp 19294-19344,50000-50100 --filter-l7 discord,stun'){
            $parts[$i]='--filter-udp 19294-19344,50000-50100 --filter-l7 discord,stun --out-range a --payload all --lua-desync fake:blob=quic_google:ip_ttl=4:repeats=2:payload=all:dir=out'
            $changed++
        }
    }
    if($changed -ne 1){throw 'Expected exactly one Discord voice UDP profile'}
    return $parts -join ' --new '
}
function BVoiceEvent([string]$Line){
    $m=[regex]::Match($Line,'^\[(?<time>\d{4}-\d\d-\d\d [\d:.]+)\].*\(socket_client\.cpp:\d+\): Ping (?:(?:received from (?<reply>[\d.]+:\d+), seq: \d+, rtt: (?<rtt>\d+))|(?:timeout from: (?<timeout>[\d.]+:\d+), seq: \d+))')
    if(-not $m.Success){return $null}
    return [pscustomobject]@{Time=[datetime]::Parse($m.Groups['time'].Value,[Globalization.CultureInfo]::InvariantCulture);Kind=$(if($m.Groups['reply'].Success){'Reply'}else{'Timeout'});Endpoint=$(if($m.Groups['reply'].Success){$m.Groups['reply'].Value}else{$m.Groups['timeout'].Value});RTT=$(if($m.Groups['reply'].Success){[int]$m.Groups['rtt'].Value}else{$null})}
}
function BSetDiscordVoice([ValidateSet('continuous-ttl4','legacy')][string]$Mode){
    $before=BRead $BuilderActive
    if(-not $before){throw 'Нет применённого состава.'}
    if($before.Model.Engine -ne 'winws2'){throw 'Этот режим голоса предназначен для winws2. Сейчас выбран исходный старый состав.'}
    $saved=BRead "$BuilderDir/discord-voice-original.json"
    $parts=@($before.ServiceImage -split ' --new ')
    $voice=@($parts|Where-Object {$_ -match '--filter-udp 19294-19344,50000-50100 --filter-l7 discord,stun'})
    if($voice.Count -ne 1){throw 'Не найден единственный голосовой профиль.'}
    if(-not $saved){
        if($before.Model.DiscordVoiceMode -eq 'continuous-ttl4'){throw 'Нет резервной копии исходного голосового профиля.'}
        $saved=@{Profile=$voice[0]};BSave $saved "$BuilderDir/discord-voice-original.json"
    }
    $image=if($Mode -eq 'continuous-ttl4'){BVoiceContinuousImage $before.ServiceImage}else{($parts|ForEach-Object {if($_ -ceq $voice[0]){$saved.Profile}else{$_}})-join ' --new '}
    $next=$before|ConvertTo-Json -Depth 12|ConvertFrom-Json
    $next.Model|Add-Member -NotePropertyName DiscordVoiceMode -NotePropertyValue $Mode -Force
    $next.ServiceImage=$image;$next.ModelHash=BHash (BBuild $next.Model);$next.Applied=(Get-Date).ToString('s')
    $draft=BRead $BuilderDraft;$follow=BRead "$BuilderDir/vpn-follow.json"
    $snapshot=BSnapshot;$success=$false
    try{
        BPause $snapshot
        BValidate $image
        $command=ConvertTo-ZapretServiceCommand $image "$BuilderDir/service-configs"
        if(Get-Service $BuilderService -ErrorAction SilentlyContinue){Set-ZapretServiceCommand $BuilderService $command}
        else{New-Service -Name $BuilderService -DisplayName 'MyZapret — winws2' -BinaryPathName $command -StartupType Manual|Out-Null}
        $start=@($snapshot.Services|Where-Object Name -eq $BuilderService|Select-Object -First 1)
        Set-Service $BuilderService -StartupType $(if($start.Count -and $start[0].Start -eq 2){'Automatic'}else{'Manual'})
        BSave $before "$BuilderDir/previous.json"
        BSave $next $BuilderActive
        if($draft){$draftNext=$draft|ConvertTo-Json -Depth 12|ConvertFrom-Json;$draftNext|Add-Member -NotePropertyName DiscordVoiceMode -NotePropertyValue $Mode -Force;BSave $draftNext $BuilderDraft}
        BFollowWant $true
        if(-not(Vpn-Connected)){BRunImage $image}
        BSave @{Mode=$Mode;Time=(Get-Date).ToString('s');Confirmed=$false;Note='Изменён только профиль голоса UDP. Требуется проверка в голосовом канале.'} "$BuilderDir/discord-voice-change.json"
        $success=$true
        "Голос Discord: $Mode. Остальные профили сохранены. Результат голоса пока не подтверждён."
    }finally{
        if(-not $success){BSave $before $BuilderActive;if($draft){BSave $draft $BuilderDraft};if($follow){BSave $follow "$BuilderDir/vpn-follow.json"};BRestore $snapshot $true}
    }
}

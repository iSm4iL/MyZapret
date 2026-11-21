param([int]$WaitMinutes=720,[int]$PhaseSeconds=60,[switch]$AllAlts)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
. "$PSScriptRoot/builder-core.ps1"
. "$PSScriptRoot/discord-voice-lib.ps1"
BInitialize
$dir=Join-Path "$PackageRoot/reports" ('Discord-Voice-'+(Get-Date -Format yyyyMMdd-HHmmss))
[void][IO.Directory]::CreateDirectory($dir)
$stateFile="$BuilderDir/discord-voice-test.json"
$mutex=[Threading.Mutex]::new($false,'Local\ZapretCustomBuilder')
$owned=$false;$guard=$null;$snapshot=$null
$single=[Threading.Mutex]::new($false,'Local\MyZapretDiscordVoiceTest')
if(-not $single.WaitOne(0)){$single.Dispose();$mutex.Dispose();return}
function VoiceState($state,$message){BSave @{State=$state;Message=$message;PID=$PID;Report=$dir;Time=(Get-Date).ToString('s')} $stateFile}
try{
    if(Test-Path "$BuilderDir/discord-voice-cancel.flag"){Remove-Item "$BuilderDir/discord-voice-cancel.flag"}
    VoiceState Waiting 'Ожидаю отключения VPN. Оставьте Discord в голосовом канале. При смене этапа переподключайтесь, если голос оборвался. Ожидание VPN — до 12 часов.'
    $until=[datetime]::UtcNow.AddMinutes($WaitMinutes)
    while(Vpn-Connected){
        if(Test-Path "$BuilderDir/discord-voice-cancel.flag"){throw 'Проверка отменена до запуска.'}
        if([datetime]::UtcNow -gt $until){throw 'VPN не отключён за время ожидания; тест не запускался.'}
        Start-Sleep -Seconds 2
    }
    Start-Sleep -Seconds 4
    $owned=$mutex.WaitOne(0)
    if(-not $owned){throw 'Сейчас выполняется другой тест или применение стратегии.'}
    $guard=BControlLock 45000
    if(-not $guard){throw 'Не удалось получить управление службой.'}
    if(Test-Path "$BuilderDir/discord-voice-cancel.flag"){Remove-Item "$BuilderDir/discord-voice-cancel.flag"}
    $active=BRead $BuilderActive
    if(-not $active){throw 'Нет применённой стратегии.'}
    if($AllAlts){
        if($active.Model.Engine -ne 'winws'){throw 'Проверка старых ALT требует активного winws.'}
        $profiles=& {
            . "$PackageRoot/legacy/zapret_tool/zapret_core.ps1"
            foreach($name in Get-Configs){
                $profile=@((Build-ImagePath $name $false) -split ' --new ' | Where-Object {$_ -match '--filter-l7 discord,stun'})
                if($profile.Count -ne 1){throw "Нет однозначного профиля UDP Discord: $name"}
                [pscustomobject]@{Name=$name;Rule=($profile[0] -replace '^.*?(--filter-udp )','$1')}
            }
        }
        $parts=@($active.ServiceImage -split ' --new ')
        $slot=@(0..($parts.Count-1)|Where-Object {$parts[$_] -match '^--filter-udp .* --filter-l7 discord,stun'})
        if($slot.Count -ne 1){throw 'Не найден единственный профиль Discord в текущем составе.'}
        $phases=@(@{Name='Текущий ALT13 + Spotify';Image=$active.ServiceImage})
        foreach($group in ($profiles|Group-Object Rule)){
            $copy=$parts.Clone()
            $copy[$slot[0]]=$group.Group[0].Rule
            $phases+=@{Name=($group.Group.Name -join ', ');Image=($copy -join ' --new ')}
        }
    }else{
        $phases=@(@{Name='Текущая обработка UDP';Image=$active.ServiceImage},@{Name='Голос UDP без обработки';Image=(BVoiceBypassImage $active.ServiceImage)},@{Name='Голос UDP: постоянная обработка TTL4';Image=(BVoiceContinuousImage $active.ServiceImage)})
    }
    $snapshot=BSnapshot;BPause $snapshot
    $logs=@("$env:APPDATA/discord/logs/discord-webrtc_0","$env:APPDATA/discord/logs/discord-last-webrtc_0")
    $results=@()
    foreach($phase in $phases){
        if(Vpn-Connected){throw 'VPN включён; проверка отменена.'}
        BRunImage $phase.Image
        $start=Get-Date;$seen=@{};$events=New-Object Collections.Generic.List[object]
        VoiceState Running ($phase.Name+'. Оставайтесь в голосовом канале. Если Discord отключился — переподключитесь к каналу.')
        while(((Get-Date)-$start).TotalSeconds -lt $PhaseSeconds){
            if(Vpn-Connected){throw 'VPN включился во время проверки; результаты этого этапа недействительны.'}
            if(Test-Path "$BuilderDir/discord-voice-cancel.flag"){throw 'Проверка отменена пользователем.'}
            foreach($log in $logs){
                foreach($line in @(Get-Content $log -Tail 2000 -ErrorAction SilentlyContinue)){
                    $event=BVoiceEvent $line
                    if($event -and $event.Time -ge $start -and -not $seen.ContainsKey($line)){$seen[$line]=$true;$events.Add($event)}
                }
            }
            Start-Sleep -Seconds 2
        }
        $ok=@($events|Where-Object Kind -eq 'Reply');$timeouts=@($events|Where-Object Kind -eq 'Timeout')
        $status=if($ok.Count -ge 6 -and $timeouts.Count -eq 0){'UDP-ping стабилен в этом этапе'}elseif(-not $events.Count){'Нет голосового трафика в журнале; этап не подтверждён'}else{'Есть потери или недостаточно ответов'}
        $results+=[pscustomobject]@{Phase=$phase.Name;Replies=$ok.Count;Timeouts=$timeouts.Count;AverageMs=$(if($ok.Count){[math]::Round(($ok|Measure-Object RTT -Average).Average,1)}else{$null});Endpoints=(@($events.Endpoint|Sort-Object -Unique)-join ', ');Status=$status}
        $events|Export-Csv "$dir/events-$($results.Count).csv" -NoTypeInformation -Encoding UTF8
        $results|Export-Csv "$dir/results.csv" -NoTypeInformation -Encoding UTF8
    }
    $results|ConvertTo-Html -Head '<meta charset="utf-8"><style>body{font:15px Segoe UI;margin:24px}td,th{border:1px solid #bbb;padding:8px}table{border-collapse:collapse}</style>' -PreContent '<h1>Discord: голосовой UDP-ping</h1><p>Сравнение вариантов обработки голосового UDP. Стабильный ping не подтверждает передачу звука в обе стороны. Если соединение уже блокировалось, может понадобиться переподключение к каналу. Постоянная стратегия не меняется.</p>'|Set-Content "$dir/table.html" -Encoding UTF8
    $finished=$true
}catch{
    VoiceState Failed $_.Exception.Message
}finally{
    try{
        if($snapshot){BRestore $snapshot $true}
        if($finished){VoiceState Complete ('Исходная стратегия восстановлена. Отчёт: '+$dir)}
    }catch{VoiceState Failed ('Ошибка восстановления исходной стратегии: '+$_.Exception.Message)}
    finally{if($guard){$guard.Dispose()};if($owned){[void]$mutex.ReleaseMutex()};$mutex.Dispose();[void]$single.ReleaseMutex();$single.Dispose()}
}

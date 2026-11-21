param([int]$WaitMinutes=720,[int]$VoiceSeconds=65,[switch]$ApplyDraft)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$OutputEncoding=[Text.Encoding]::UTF8
. "$PSScriptRoot/builder-core.ps1"
$single=[Threading.Mutex]::new($false,'Local\MyZapretCheckCurrent')
if(-not $single.WaitOne(0)){$single.Dispose();exit 1}
$dir=Join-Path "$PackageRoot/reports" ('Current-'+(Get-Date -Format yyyyMMdd-HHmmss))
[void][IO.Directory]::CreateDirectory($dir)
function CurrentState($state,$message){BSave @{State=$state;Message=$message;Report=$dir;Time=(Get-Date).ToString('s');PID=$PID} "$BuilderDir/current-check.json"}
try{
    Remove-Item -LiteralPath "$BuilderDir/current-cancel.flag" -ErrorAction SilentlyContinue
    CurrentState Waiting 'Ожидаю отключения VPN. Затем проверю применённый состав и голос Discord. Оставайтесь в голосовом канале.'
    $deadline=[datetime]::UtcNow.AddMinutes($WaitMinutes)
    while((BVpnState) -ne 'Off'){
        if(Test-Path "$BuilderDir/current-cancel.flag"){throw 'Проверка отменена.'}
        if([datetime]::UtcNow -gt $deadline){throw 'VPN не отключён; проверка не запускалась.'}
        Start-Sleep -Seconds 2
    }
    Start-Sleep -Seconds 4
    if($ApplyDraft){
        CurrentState Running 'Применяю черновик, затем проверю подключение.'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$BuilderLab/builder-job.ps1" -Action Apply > "$dir/apply.log" 2> "$dir/apply-errors.log"
        if($LASTEXITCODE -ne 0){throw 'Состав не применён. Причина в apply-errors.log; исходная служба восстановлена обработчиком применения.'}
    }
    $active=BRead $BuilderActive
    if(-not $active){throw 'Нет применённого состава.'}
    $hash=BHash $active.ServiceImage
    CurrentState Running ('Проверяю все сервисы: '+$active.Model.Name)
    BSave @{Groups=@($BuilderCatalog.Keys);UseActive=$true} "$dir/request.json"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$BuilderLab/builder-job.ps1" -Action TestMine -RequestFile "$dir/request.json" > "$dir/sites.log" 2> "$dir/sites-errors.log"
    if($LASTEXITCODE -ne 0){throw 'Не выполнена проверка сервисов. Причина в sites-errors.log.'}
    if(Vpn-Connected){throw 'VPN включён; результат не подтверждён.'}
    if(Test-Path "$BuilderDir/current-cancel.flag"){throw 'Проверка отменена.'}
    $sites=BRead "$BuilderDir/mine-results.json"
    if($sites.ModelHash -cne (BHash (BBuild $active.Model))){throw 'Проверялся другой состав; результат не подтверждён.'}
    $sites.Rows|Export-Csv "$dir/sites.csv" -NoTypeInformation -Encoding UTF8
    Get-DnsClientServerAddress -AddressFamily IPv4|Select-Object InterfaceAlias,ServerAddresses|ConvertTo-Json -Depth 5|Set-Content "$dir/dns.json" -Encoding UTF8
    Get-DnsClientNrptPolicy -Effective|Select-Object Namespace,NameServers|ConvertTo-Json -Depth 5|Set-Content "$dir/dns-rules.json" -Encoding UTF8
    CurrentState Running 'Сайты проверены. Собираю 65 секунд голосовых UDP-ping Discord. Если не в канале — войдите сейчас.'
    $start=Get-Date;$seen=@{};$events=@()
    while(((Get-Date)-$start).TotalSeconds -lt $VoiceSeconds){
        if(Vpn-Connected){throw 'VPN включён; проверка голоса прервана.'}
        if(Test-Path "$BuilderDir/current-cancel.flag"){throw 'Проверка отменена.'}
        if((BHash (BRead $BuilderActive).ServiceImage) -cne $hash){throw 'Состав изменён во время проверки.'}
        foreach($name in @('discord-webrtc_0','discord-last-webrtc_0')){
            foreach($line in @(Get-Content "$env:APPDATA/discord/logs/$name" -Tail 2000 -ErrorAction SilentlyContinue)){
                $event=BVoiceEvent $line
                if($event -and $event.Time -ge $start -and -not $seen.ContainsKey($line)){$seen[$line]=$true;$events+=$event}
            }
        }
        Start-Sleep -Seconds 2
    }
    $replies=@($events|Where-Object Kind -eq Reply);$timeouts=@($events|Where-Object Kind -eq Timeout)
    $voice=if($replies.Count -ge 6 -and -not $timeouts.Count){'UDP-ping стабилен; звук в обе стороны подтвердите в канале.'}elseif(-not $events.Count){'Нет новых голосовых ping: голос НЕ проверен.'}else{"Голос: ответов $($replies.Count), таймаутов $($timeouts.Count). Стабильность НЕ подтверждена."}
    $events|Export-Csv "$dir/voice.csv" -NoTypeInformation -Encoding UTF8
    . "$BuilderLab/current-report.ps1"
    BWriteCurrentReport $active @($sites.Rows) $voice $dir
    BSave @{SourceHash=$hash;Replies=$replies.Count;Timeouts=$timeouts.Count;Message=$voice;Time=(Get-Date).ToString('s');Report=$dir} "$BuilderDir/voice-result.json"
    CurrentState Complete ("Сайты: $(@($sites.Rows|Where-Object Pass).Count)/$(@($sites.Rows).Count). $voice Отчёт: $dir")
    Start-Process "$dir/table.html"
}catch{CurrentState Failed ($_.Exception.Message+' Отчёт: '+$dir);exit 1}
finally{[void]$single.ReleaseMutex();$single.Dispose()}

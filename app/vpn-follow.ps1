$FollowTask='MyZapret-VPN-follow'
function BControlLock([int]$WaitMs=0){
    $until=[datetime]::UtcNow.AddMilliseconds($WaitMs)
    do{
        try{return [IO.File]::Open("$BuilderDir/runtime.lock",[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
        catch [IO.IOException]{if([datetime]::UtcNow -ge $until){return $null};Start-Sleep -Milliseconds 100}
    }while($true)
}
function BBootId {return [string](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' -Name BootId -ErrorAction Stop).BootId}
function BVpnState {
    $vpnService=Get-Service -Name VpnusService -ErrorAction SilentlyContinue
    if($vpnService -and $vpnService.Status -eq 'Stopped'){return 'Off'}
    if(-not $vpnService -and -not(Test-Path -LiteralPath $VpnLog) -and -not(Test-Path 'HKLM:/SYSTEM/CurrentControlSet/Services/VpnusService')){return 'Off'}
    $last=Get-Content $VpnLog -Tail 300 -Encoding UTF8 -ErrorAction SilentlyContinue|Where-Object {$_ -match '\[tunnel\] (?:(?:dis)?connected\s*$|connect: bringing up tunnel)'}|Select-Object -Last 1
    if(-not $last){return 'Unknown'}
    if($last -match '\] disconnected\s*$'){return 'Off'}
    return 'On'
}
function BFollowWant([bool]$want){
    $state=BRead "$BuilderDir/vpn-follow.json"
    if(-not $state){$state=[pscustomobject]@{Enabled=$false;DesiredRunning=$want;BootId=(BBootId)}}
    $state.DesiredRunning=$want;$state.BootId=BBootId
    BSave $state "$BuilderDir/vpn-follow.json"
}
function BFollowInstall {
    if(Get-ScheduledTask -TaskName $FollowTask -ErrorAction SilentlyContinue){Stop-ScheduledTask -TaskName $FollowTask}
    $action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "'+$BuilderLab+'\vpn-watch.ps1"')
    $trigger=New-ScheduledTaskTrigger -AtStartup
    $principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([timespan]::Zero) -RestartCount 3 -RestartInterval ([timespan]::FromMinutes(1)) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $FollowTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force|Out-Null
    Start-ScheduledTask -TaskName $FollowTask
}
function BFollowStatus([string]$message){
    $previous=BRead "$BuilderDir/vpn-status.json"
    if($previous.Message -ne $message){BSave @{Message=$message;Time=(Get-Date).ToString('s')} "$BuilderDir/vpn-status.json"}
    return $message
}
function BFollowStep {
    $state=BRead "$BuilderDir/vpn-follow.json"
    if(-not $state.Enabled){return BFollowStatus 'VPN-авто выключено'}
    $svc=Get-Service $BuilderService -ErrorAction SilentlyContinue
    if(-not $svc){return BFollowStatus 'Сначала примените состав MyZapret'}
    if($state.BootId -ne (BBootId)){
        $state.BootId=BBootId
        $state.DesiredRunning=(Get-ItemProperty "HKLM:/SYSTEM/CurrentControlSet/Services/$BuilderService").Start -eq 2
        BSave $state "$BuilderDir/vpn-follow.json"
    }
    $vpn=BVpnState
    if($vpn -eq 'Unknown'){return BFollowStatus 'Состояние VPN неизвестно; автозапуск отложен'}
    if($vpn -eq 'On'){
        if($svc.Status -eq 'Running'){BStopService $BuilderService}
        return BFollowStatus 'VPN включён: MyZapret приостановлен'
    }
    if(-not $state.DesiredRunning){return BFollowStatus 'Ручной стоп: MyZapret не возобновляется'}
    $health=BRead "$BuilderDir/driver-health.json"
    if($health.NeedsRestart -and $health.BootId -eq (BBootId)){return BFollowStatus 'WinDivert требует перезагрузки Windows. После перезапуска MyZapret возобновится автоматически.'}
    if($svc.Status -ne 'Running'){
        if(Get-Process winws,winws2 -ErrorAction SilentlyContinue){return BFollowStatus 'Другой движок уже запущен; MyZapret не включён'}
        $active=BRead $BuilderActive
        $image=[string](Get-ItemProperty "HKLM:/SYSTEM/CurrentControlSet/Services/$BuilderService").ImagePath
        if(-not $active -or $image -cne (ConvertTo-ZapretServiceCommand $active.ServiceImage "$BuilderDir/service-configs")){return BFollowStatus 'Состав службы не подтверждён; примените ALT заново'}
        BStartManagedService
        (Get-Service $BuilderService).WaitForStatus('Running',[timespan]::FromSeconds(15))
    }
    return BFollowStatus 'VPN выключен: применённый MyZapret работает'
}

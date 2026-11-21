function BRepairDriver {
    if(Get-Process winws,winws2 -ErrorAction SilentlyContinue){throw 'Сначала остановите работающий zapret. Драйвер не изменён.'}
    $driver=Get-CimInstance Win32_SystemDriver -Filter "Name='WinDivert'"
    if(-not $driver){BSave @{NeedsRestart=$false;BootId=(BBootId)} "$BuilderDir/driver-health.json";return 'Драйвер освобождён; его загрузит движок.'}
    $path=([string]$driver.PathName).Replace('\??\','').Trim('"')
    $ownedRoot=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\')+'\'
    $driverPath=[IO.Path]::GetFullPath($path)
    $legacyPath=Join-Path (Split-Path $PackageRoot) 'bin/WinDivert64.sys'
    if(-not $driverPath.StartsWith($ownedRoot,[StringComparison]::OrdinalIgnoreCase)){
        $bundledPath=Join-Path $PackageRoot 'bin/WinDivert64.sys'
        if($driverPath -ine $legacyPath -or -not(Test-Path -LiteralPath $driverPath) -or
            -not(Test-Path -LiteralPath $bundledPath) -or
            (Get-FileHash -LiteralPath $driverPath).Hash -cne (Get-FileHash -LiteralPath $bundledPath).Hash){
            throw "WinDivert принадлежит другой установке: $path. Автоматическое восстановление отменено."
        }
    }
    $owners=@(Get-Process|ForEach-Object {try{$p=$_;foreach($m in @($p.Modules|Where-Object ModuleName -match '^WinDivert.*\.dll$')){$p.ProcessName}}catch{}})
    if($owners.Count){throw ('WinDivert используется: '+($owners -join ', ')+'. Закройте эти программы; драйвер не изменён.')}
    if($driver.State -ne 'Stopped'){
        & sc.exe stop WinDivert|Out-Null
        if($LASTEXITCODE -ne 0){throw 'Windows не освободила драйвер WinDivert. Другие сетевые службы не затронуты.'}
        $deadline=[datetime]::UtcNow.AddSeconds(15)
        do{$driver=Get-CimInstance Win32_SystemDriver -Filter "Name='WinDivert'";if(-not $driver -or $driver.State -eq 'Stopped'){break};Start-Sleep -Milliseconds 250}while([datetime]::UtcNow -lt $deadline)
        if($driver -and $driver.State -ne 'Stopped'){
            BSave @{NeedsRestart=$true;BootId=(BBootId);Time=(Get-Date).ToString('s');Reason='WinDivert stop pending'} "$BuilderDir/driver-health.json"
            throw 'Драйвер WinDivert завис при выгрузке. Сохраните работу и перезагрузите Windows. Настройки подготовлены; повторные нажатия не помогут.'
        }
    }
    if($driver){
        & sc.exe config WinDivert start= demand|Out-Null
        if($LASTEXITCODE -ne 0){throw 'Не удалось восстановить ручной запуск драйвера.'}
    }
    BSave @{NeedsRestart=$false;BootId=(BBootId)} "$BuilderDir/driver-health.json"
    return 'Наш WinDivert освобождён, ручной запуск восстановлен. VPN и DNS не менялись.'
}
function BStartManagedService {
    $command=[string](Get-ItemProperty "HKLM:/SYSTEM/CurrentControlSet/Services/$BuilderService").ImagePath
    $tokens=@([regex]::Matches($command,'(?:[^\s"]|"[^"]*")+')|ForEach-Object {$_.Value.Trim('"')})
    $log=if($tokens[-1].EndsWith('.json')){$tokens[-1]+'.log'}else{''}
    for($attempt=0;$attempt -lt 3;$attempt++){
        $offset=if($log -and (Test-Path $log)){[IO.File]::ReadAllText($log).Length}else{0}
        try{
            Start-Service $BuilderService -ErrorAction Stop
            Start-Sleep -Seconds 2
            if((Get-Service $BuilderService).Status -ne 'Running'){throw 'Движок завершился сразу после запуска.'}
            return
        }catch{
            $failure=$_.Exception.Message
            $details=if($log -and (Test-Path $log)){$text=[IO.File]::ReadAllText($log);$text.Substring([Math]::Min($offset,$text.Length))}else{''}
            $conflict=$details -match 'object is referenced by other objects|FWP_E_IN_USE|0x8032000[Aa]|already running with the same filter|FWP_E_ALREADY_EXISTS'
            if($conflict -and $attempt -lt 2){
                BStopService $BuilderService
                if($attempt -eq 1){BRepairDriver|Out-Null}
                Start-Sleep -Seconds (2+2*$attempt)
                continue
            }
            if($conflict){throw "Не запустился перехват трафика WinDivert. Служба не работает; результаты сети не проверялись.`n$details"}
            throw "Не запустилась служба MyZapret: $failure`n$details"
        }
    }
}

param([ValidateSet('InstallAlt13Spotify','InstallStockDiscord','RepairDriver','ModernDraft','InstallLegacy','PreviousPreset','VoiceContinuous','VoiceLegacy','InstallVerified','ShareDNS','ShareDNSUndo','ShareDisable','ShareRestore','Initialize','VideoUrl','Rename','Base','Take','Filters','ResetFilters','ResetDraft','Apply','Rollback','TestMine','TestDonors','AutoOn','AutoOff','RepairAll','CompareYouTube','DnsCheck','FollowOn','FollowOff','Stop','DisableOld','Restore','SelfTest')][string]$Action='Initialize',[string]$RequestFile)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
. "$PSScriptRoot/builder-core.ps1"
BInitialize
. "$PSScriptRoot/share-tools.ps1"
$request=if($RequestFile){BRead $RequestFile}else{$null}
$mutex=[Threading.Mutex]::new($false,'Local\ZapretCustomBuilder')
if(-not $mutex.WaitOne(0)){$mutex.Dispose();throw 'Another builder operation is running.'}
$lock=$null;$runtimeGuard=$null;$snapshot=$null;$changed=$false
try{
    $runtimeGuard=BControlLock 5000
    if(-not $runtimeGuard){throw 'Выполняется автоматическое переключение VPN. Повторите действие через несколько секунд.'}
    $model=BRead $BuilderDraft
    switch($Action){
        ShareDNS {DnsApply ([int]$request.Index);'Раздельные DNS настроены. Перезапустите браузер и Spotify.';return}
        ShareDNSUndo {DnsRestore;'Прежние DNS восстановлены.';return}
        ShareDisable {DisableOtherZapret (FindOtherZapret);'Другие zapret отключены. Состояние сохранено.';return}
        ShareRestore {RestoreOtherZapret;'Прежние zapret восстановлены.';return}
        RepairDriver {BStopService $BuilderService;BRepairDriver;return}
        ModernDraft {
            $previous=BRead "$BuilderDir/previous.json"
            $next=if($previous.Model.Engine -eq 'winws2'){$previous.Model}else{BNewModel '02-fake-ts'}
            BSave $next $BuilderDraft
            'Конструктор включён. Можно тестировать и переносить сервисы. Рабочий состав ещё не заменён.';return
        }
        InstallAlt13Spotify {
            $preset=[pscustomobject]@{Name='ALT13 + Spotify';Engine='winws';BaseName='alt13-spotify';Selections=@{};GameFilter=$false;IpsetLoaded=$false}
            BInstallStoredPreset -Model $preset
            return
        }
        InstallStockDiscord {BInstallStoredPreset -StockDiscord;return}
        InstallLegacy {BInstallStoredPreset;return}
        PreviousPreset {BInstallStoredPreset -Previous;return}
        VoiceContinuous {BSetDiscordVoice continuous-ttl4;return}
        VoiceLegacy {BSetDiscordVoice legacy;return}
        InstallVerified {BInstallVerifiedDefault;return}
        Initialize {'MyZapret winws2 ready.';return}
        VideoUrl { BSetVideo ([string]$request.Url);'Тестовый ролик сохранён. В следующем тесте YouTube поток будет получен автоматически.';return }
        Rename {
            $name=[string]$request.Name
            if([string]::IsNullOrWhiteSpace($name) -or $name.Length -gt 80){throw 'Name must contain 1–80 characters.'}
            $model.Name=$name;BSave $model $BuilderDraft;'Draft name saved.';return
        }
        Base {
            BCheckDonor ([string]$request.Donor)
            if($model.Engine -eq 'winws'){$model.Name='Мой состав'}
            $model.Engine='winws2'
            $model.BaseName=[string]$request.Donor
            $model|Add-Member -NotePropertyName BaseImage -NotePropertyValue $model.BaseName -Force
            $model.Selections=[ordered]@{}
            [void](BBuild $model);BSave $model $BuilderDraft;'Draft base changed; site selections reset. Running ALT unchanged.';return
        }
        Take {
            if(-not $BuilderCatalog.Contains([string]$request.Group)){throw 'Unknown service.'}
            $data=BRead "$BuilderDir/donor-results.json"
            if(-not $data -or $data.ProbeHash -ne (BProbeHash) -or $data.BaseHash -ne (BBaseHash $model)){throw 'Donor tests use another base or game filter. Run donor tests again.'}
            $row=@($data.Rows|Where-Object {$_.Donor -eq $request.Donor -and $_.Group -eq $request.Group -and $_.Pass -and $_.Total -eq $BuilderProbeGroups[[string]$request.Group].Count})
            if(-not $row.Count){throw 'Нет успешной проверки этого сервиса у донора. Для YouTube нужны и страницы, и получение видеофрагмента.'}
            $model=BWithDonor $model ([string]$request.Group) ([string]$request.Donor)
            [void](BBuild $model);BSave $model $BuilderDraft
            "COPIED INTO DRAFT: $($request.Group) <- $($request.Donor). Running ALT unchanged.";return
        }
        ResetDraft {
            $active=BRead $BuilderActive
            if(-not $active){throw 'No applied ALT to restore the draft from.'}
            BSave $active.Model $BuilderDraft;'Draft reset to the applied ALT.';return
        }
        Filters {
            if($model.Engine -eq 'winws'){throw 'Старый состав сохраняется точно. Для изменения фильтров сначала выберите базу winws2.'}
            $model|Add-Member -NotePropertyName GameFilter -NotePropertyValue ([bool]$request.GameFilter) -Force
            $model|Add-Member -NotePropertyName IpsetLoaded -NotePropertyValue ([bool]$request.IpsetLoaded) -Force
            [void](BBuild $model);BSave $model $BuilderDraft
            "Draft filters saved: GameFilter=$($model.GameFilter), IPSet=$($model.IpsetLoaded). Apply to restart.";return
        }
        ResetFilters {
            if($model.Engine -eq 'winws'){throw 'У старого состава фильтры уже сохранены в снимке.'}
            $model|Add-Member -NotePropertyName GameFilter -NotePropertyValue $false -Force
            $model|Add-Member -NotePropertyName IpsetLoaded -NotePropertyValue $false -Force
            BSave $model $BuilderDraft;'Draft Game Filter and IPSet reset. Other fragments preserved.';return
        }
        SelfTest { & "$PSScriptRoot/self-test.ps1";return }
        FollowOn {
            BFollowWant ([bool](BRead $BuilderActive))
            $follow=BRead "$BuilderDir/vpn-follow.json";$follow.Enabled=$true;BSave $follow "$BuilderDir/vpn-follow.json"
            try{BFollowInstall}catch{$follow.Enabled=$false;BSave $follow "$BuilderDir/vpn-follow.json";throw}
            BFollowStep
            'VPN-авто включено. Работает и при закрытой панели; VPN подключайте самостоятельно.';return
        }
        FollowOff {
            $follow=BRead "$BuilderDir/vpn-follow.json"
            if($follow){$follow.Enabled=$false;BSave $follow "$BuilderDir/vpn-follow.json"}
            if(Get-ScheduledTask -TaskName $FollowTask -ErrorAction SilentlyContinue){Disable-ScheduledTask -TaskName $FollowTask|Out-Null;Stop-ScheduledTask -TaskName $FollowTask}
            'VPN-авто выключено. Текущее состояние MyZapret сохранено.';return
        }
        Stop {BFollowWant $false;BStopService $BuilderService;'Custom ALT stopped. Auto-start setting unchanged.';return}
        DisableOld {
            $snapshot=BSnapshot
            if(-not(Test-Path $BuilderOriginal)){BSave $snapshot $BuilderOriginal}
            $changed=$true
            foreach($task in $snapshot.Tasks){Disable-ScheduledTask -TaskName $task.Name -TaskPath $task.Path|Out-Null;if($task.Running){Stop-ScheduledTask -TaskName $task.Name -TaskPath $task.Path}}
            foreach($s in $snapshot.Services){
                if($s.Name -eq $BuilderService){continue}
                Set-Service $s.Name -StartupType Disabled
                BStopService $s.Name
                "Отключена служба: $($s.Name) (остановлена, автозапуск выключен)."
            }
            $changed=$false
            'Старые службы zapret и их автозадачи отключены. MyZapret не изменён. Для возврата — «Прежний zapret».'
            if(Get-Process winws -ErrorAction SilentlyContinue){'Остался вручную запущенный winws: закройте его окно отдельно.'}
            return
        }
        AutoOn {
            $active=BRead $BuilderActive
            if(-not $active -or -not(Get-Service $BuilderService -ErrorAction SilentlyContinue)){throw 'Apply your ALT first.'}
            if((Get-ItemProperty "HKLM:/SYSTEM/CurrentControlSet/Services/$BuilderService").ImagePath -cne (ConvertTo-ZapretServiceCommand $active.ServiceImage "$BuilderDir/service-configs")){throw 'Service config differs from saved ALT. Apply it again.'}
            Set-Service $BuilderService -StartupType Automatic
            'Windows auto-start ENABLED for the APPLIED custom ALT, not the draft.';return
        }
        AutoOff {if(Get-Service $BuilderService -ErrorAction SilentlyContinue){Set-Service $BuilderService -StartupType Manual};'Windows auto-start disabled.';return}
    }
    if($Action -eq 'RepairAll'){
        if(Test-Path "$BuilderDir/cancel.flag"){Remove-Item -LiteralPath "$BuilderDir/cancel.flag"}
        if(Vpn-Connected){
            $runtimeGuard.Dispose();$runtimeGuard=$null
            $until=[datetime]::UtcNow.AddHours(1)
            BSave @{Donor='Полное восстановление YouTube';Index=0;Total=1;Stage='Ожидаю отключения VPN (до 1 часа)'} "$BuilderDir/progress.json"
            while(Vpn-Connected){
                if(Test-Path "$BuilderDir/cancel.flag"){throw 'Cancelled; original state will be restored.'}
                if([datetime]::UtcNow -gt $until){throw 'VPN не был отключён за час; проверка не запускалась.'}
                Start-Sleep -Seconds 2
            }
            Start-Sleep -Seconds 3
            $runtimeGuard=BControlLock 5000
            if(-not $runtimeGuard){throw 'Не удалось получить управление службами после отключения VPN.'}
        }
    }
    if(Vpn-Connected){throw 'Disconnect VPN before applying or testing ALT. Draft remains saved.'}
    $flag=Join-Path $Store 'test_active.flag'
    try{$lock=[IO.File]::Open($flag,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)}catch{throw 'Another zapret test is active.'}
    if($Action -eq 'RepairAll'){
        $model=BRead $BuilderDraft
        $snapshot=BSnapshot;$changed=$true;BPause $snapshot
        $script:BRRequireNoVpn=$true
        if((Test-Path "$BuilderDir/focused-next.json") -or (BRead "$BuilderDir/repair-results.json").PlanVersion -eq 'focused-v1'){if(Test-Path "$BuilderDir/focused-next.json"){Remove-Item -LiteralPath "$BuilderDir/focused-next.json"};& "$BuilderLab/focused-youtube.ps1"}else{& "$BuilderLab/repair-youtube.ps1"}
        $proof=BRead "$BuilderDir/repair-results.json"
        if(-not $proof.Confirmed -or (-not $proof.Recommended -and -not $proof.ProxyMode -and -not $proof.PacketMethod)){'Автоприменения нет: повторно подтверждённого кандидата не найдено. Результаты веток сохранены.';return}
        if((BHash (BBuild $model)) -ne $proof.SourceModelHash){throw 'Состав изменился во время проверки; автоприменение отменено.'}
        if(Vpn-Connected){throw 'VPN connected during test; restoring original state.'}
        BRestore $snapshot $true;$changed=$false;$snapshot=$null
        if($proof.PacketMethod){
            $model|Add-Member -NotePropertyName PacketMethod -NotePropertyValue $proof.PacketMethod -Force
            $model|Add-Member -NotePropertyName PacketIPs -NotePropertyValue @($proof.PacketIPs) -Force
        }elseif($proof.ProxyMode){
            $model|Add-Member -NotePropertyName LocalTlsProxy -NotePropertyValue ([bool]$proof.NeedsExclusion) -Force
            BSave @{Enabled=$true;Mode=$proof.ProxyMode;Confirmed=$true;Report=$proof.Report} "$BuilderDir/local-tls-proxy.json"
        }else{$model=BWithDonor $model 'youtube' ([string]$proof.Recommended)}
        BSave $model $BuilderDraft
        $Action='Apply'
        'Повторно подтверждён способ: '+$proof.Recommended+$proof.PacketMethod+$proof.ProxyMode+'. Применяю состав.'
    }
    if($Action -eq 'CompareYouTube'){
        if(Test-Path "$BuilderDir/cancel.flag"){Remove-Item -LiteralPath "$BuilderDir/cancel.flag"}
        $snapshot=BSnapshot;$changed=$true;BPause $snapshot
        & "$BuilderLab/compare-youtube.ps1"
        return
    }
    if($Action -eq 'DnsCheck'){
        if(Test-Path "$BuilderDir/cancel.flag"){Remove-Item -LiteralPath "$BuilderDir/cancel.flag"}
        & "$BuilderLab/youtube-dns-check.ps1"
        return
    }
    if($Action -eq 'Restore'){
        $saved=BRead $BuilderOriginal;if(-not $saved){throw 'No original state saved.'}
        BRestore $saved $true
        BFollowWant $false
        Remove-Item -LiteralPath $BuilderOriginal
        Remove-Item -LiteralPath $BuilderActive -ErrorAction SilentlyContinue
        'Original zapret services and startup modes restored. Draft and reports retained.';return
    }
    if($Action -eq 'Rollback'){
        $previous=BRead "$BuilderDir/previous.json"
        if(-not $previous){throw 'No previous applied ALT.'}
        $snapshot=BSnapshot
        if(-not(Test-Path $BuilderOriginal)){BSave $snapshot $BuilderOriginal}
        $changed=$true;BPause $snapshot -Permanent
        BValidate ([string]$previous.ServiceImage)
        BRunImage ([string]$previous.ServiceImage)
        $current=BRead $BuilderActive
        BSave $previous $BuilderActive;BSave $previous.Model $BuilderDraft
        if($current){BSave $current "$BuilderDir/previous.json"}
        BFollowWant $true
        $changed=$false;'Previous applied ALT restored.';return
    }
    if($Action -eq 'TestMine' -and $request.UseActive){$model=(BRead $BuilderActive).Model;if(-not $model){throw 'Нет применённого состава.'}}
    if($model.Engine -eq 'winws' -and $Action -eq 'TestDonors'){throw 'Для сравнения доноров winws2 сначала выберите базу winws2. Текущий старый состав проверяется кнопкой проверки текущего.'}
    $image=BBuild $model
    if($Action -eq 'Apply'){
        $release=Join-Path $BuilderDir ('releases/'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
        $frozen=BFreeze $image $release
        $snapshot=BSnapshot
        if(-not(Test-Path $BuilderOriginal)){BSave $snapshot $BuilderOriginal}
        $changed=$true
        BPause $snapshot -Permanent
        # winws v72 checks duplicate filters even in --dry-run. Validate after orderly shutdown.
        BValidate $frozen
        BRunImage $frozen
        $previous=BRead $BuilderActive
        if($previous){BSave $previous "$BuilderDir/previous.json"}
        BSave ([pscustomobject]@{Model=$model;ModelHash=(BHash $image);ServiceImage=$frozen;Applied=(Get-Date).ToString('s');Release=$release}) $BuilderActive
        $changed=$false
        BFollowWant $true
        'APPLIED: winws2 / myzapret2. Old engines paused. Use AutoOn for Windows startup. Hosts unchanged.';return
    }
    # Both scans test complete compositions serially and restore the previous service states.
    if(Test-Path "$BuilderDir/cancel.flag"){Remove-Item "$BuilderDir/cancel.flag"}
    $snapshot=BSnapshot;$changed=$true;BPause $snapshot
    $rows=@()
    $stamp=(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6)
    $dir=Join-Path $PackageRoot "reports/$Action-$stamp"
    New-Item -ItemType Directory -Path $dir|Out-Null
    $donors=if($Action -eq 'TestDonors'){@(Get-Configs)}else{@('MY_ALT')}
    $testedGroups=if($request -and @($request.Groups).Count){@($request.Groups)}else{@($BuilderProbeGroups.Keys)}
    foreach($group in $testedGroups){if(-not $BuilderProbeGroups.Contains($group)){throw "Unknown test group: $group"}}
    $file=if($Action -eq 'TestDonors'){'donor-results.json'}else{'mine-results.json'}
    $existing=BRead "$BuilderDir/$file"
    $sameContext=if($Action -eq 'TestDonors'){$existing -and $existing.BaseHash -eq (BBaseHash $model)}else{$existing -and $existing.ModelHash -eq (BHash $image)}
    if($existing.ProbeHash -ne (BProbeHash)){$sameContext=$false};if($sameContext){$rows=@($existing.Rows|Where-Object {$_.Group -notin $testedGroups})}
    $index=0
    foreach($donor in $donors){
        if(Test-Path "$BuilderDir/cancel.flag"){throw 'Cancelled; original state will be restored.'}
        if(Vpn-Connected){throw 'VPN connected during test; restoring original state.'}
        $index++
        $trial=$model
        if($donor -ne 'MY_ALT'){foreach($group in $testedGroups){$trial=BWithDonor $trial $group $donor}}
        $trialImage=BBuild $trial
        BSave ([pscustomobject]@{Action=$Action;Donor=$donor;Index=$index;Total=$donors.Count;Time=(Get-Date).ToString('s')}) "$BuilderDir/progress.json"
        $startupError=''
        try{BRunImage $trialImage}catch{throw ('Движок не запущен. Проверка остановлена; это не результат доступности сайтов. '+$_.Exception.Message)}
        foreach($group in $testedGroups){
            BSave ([pscustomobject]@{Action=$Action;Donor=$donor;Index=$index;Total=$donors.Count;Stage=($BuilderCatalog[$group].Label+': страницы');Time=(Get-Date).ToString('s')}) "$BuilderDir/progress.json"
            $passed=0;$details=@();$duration=0.0
            foreach($url in $BuilderProbeGroups[$group]){
                if(Test-Path "$BuilderDir/cancel.flag"){throw 'Cancelled; original state will be restored.'}
                if(Vpn-Connected){throw 'VPN connected during test; restoring original state.'}
                if($startupError){$details += $startupError;continue}
                $ErrorActionPreference='Continue'
                $raw=& curl.exe -4 -sS -L --noproxy '*' --connect-timeout 4 --max-time 8 -o NUL -w '%{http_code} %{time_total}' $url 2>> "$dir/curl-errors.txt"
                $exitCode=$LASTEXITCODE;$ErrorActionPreference='Stop'
                $p=("$raw").Trim() -split '\s+'
                if($p.Count -gt 1){$duration += [double]::Parse($p[1],[Globalization.CultureInfo]::InvariantCulture)}
                if($exitCode -eq 0 -and $p[0] -match '^[23]'){$passed++}
                $details += "$url : HTTP=$($p[0]) curl=$exitCode"
            }
            $media=$null
            if($group -eq 'youtube'){
                BSave ([pscustomobject]@{Action=$Action;Donor=$donor;Index=$index;Total=$donors.Count;Stage='YouTube: получаем и проверяем видеофрагмент';Time=(Get-Date).ToString('s')}) "$BuilderDir/progress.json"
                $media=if($startupError){[pscustomobject]@{Checked=$false;Pass=$false;Details=$startupError}}else{BVideoProbe $dir};$details += $media.Details
            }
            $rows += [pscustomobject]@{Donor=$donor;Group=$group;VideoChecked=[bool]$media.Checked;VideoPass=[bool]$media.Pass;Pass=($passed -eq $BuilderProbeGroups[$group].Count -and ($group -ne 'youtube' -or ($media.Checked -and $media.Pass)));Passed=$passed;Total=$BuilderProbeGroups[$group].Count;Seconds=[math]::Round($duration,2);Details=($details -join '; ');Time=(Get-Date).ToString('s')}
            $file=if($Action -eq 'TestDonors'){'donor-results.json'}else{'mine-results.json'}
            $data=[pscustomobject]@{Rows=$rows;ProbeHash=(BProbeHash);BaseHash=(BBaseHash $model);ModelHash=(BHash $image);ModelName=$model.Name;TestGroups=$testedGroups;Time=(Get-Date).ToString('s');Complete=$false;Report=$dir;Note='YouTube: HTTPS pages and an automatic video range over TCP/IPv4. Other services: HTTPS pages only. Full playback, audio, QUIC, voice, matchmaking and game UDP are NOT verified. 403/404 alone do not prove ISP blocking.'}
            BSave $data "$BuilderDir/$file"
            $rows|Export-Csv "$dir/results.csv" -NoTypeInformation -Encoding UTF8
        }
    }
    $data.Complete=$true;BSave $data "$BuilderDir/$file"
    $rows|ConvertTo-Html -Head '<meta charset="utf-8"><style>body{font:15px Segoe UI;margin:24px}table{border-collapse:collapse}td,th{border:1px solid #ccd;padding:8px}</style>' -PreContent ('<h1>'+[Net.WebUtility]::HtmlEncode([string]$model.Name)+'</h1><p>'+[Net.WebUtility]::HtmlEncode($data.Note)+'</p>')|Set-Content "$dir/table.html" -Encoding UTF8
    $checked=@($rows|Where-Object {$_.Group -in $testedGroups})
    $ok=@($checked|Where-Object Pass).Count
    "Проверка завершена: успешных результатов $ok из $($checked.Count). Завершение теста не означает, что все сервисы работают."
    $youtube=@($checked|Where-Object Group -eq 'youtube')
    if($youtube.Count){"YouTube (страницы + видео): прошли $(@($youtube|Where-Object Pass).Count) из $($youtube.Count)."}
    "Test complete: $dir"
}finally{
    try{if($changed -and $snapshot){BRestore $snapshot $true}}
    finally{
        if($lock){$lock.Dispose();Remove-Item -LiteralPath (Join-Path $Store 'test_active.flag') -ErrorAction SilentlyContinue}
        if(Test-Path "$BuilderDir/progress.json"){Remove-Item "$BuilderDir/progress.json"}
        if($runtimeGuard){$runtimeGuard.Dispose()}
        [void]$mutex.ReleaseMutex();$mutex.Dispose()
    }
}

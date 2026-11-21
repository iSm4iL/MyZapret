function StartControlTest {
    $state=BRead "$BuilderDir/control-test.json"
    if((BRead "$BuilderDir/current-check.json").State -in @('Waiting','Running')){Log 'Уже запущена общая проверка.';return}
    if($script:job -or $state.State -in @('Waiting','Running')){Log 'Проверка уже выполняется или ожидает VPN.';return}
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$BuilderLab+'/youtube-control-test.ps1" -TransportMatrix')
    Log 'Проверка TCP / QUIC ждёт отключения VPN. Два ролика, TLS 1.2, TLS 1.3 и HTTP3. После проверки прежний запуск будет восстановлен.'
}
function MenuAction($action,$data=$null){
    if((BRead "$BuilderDir/control-test.json").State -in @('Waiting','Running')){Log 'Сначала дождитесь окончания проверки или отмените её.';return}
    if((BRead "$BuilderDir/current-check.json").State -eq 'Running'){Log 'Дождитесь общей проверки или отмените её.';return}
    Run $action $data
}
$menu=New-Object Windows.Forms.MenuStrip
$setup=New-Object Windows.Forms.ToolStripMenuItem('Настройка')
$diagnostics=New-Object Windows.Forms.ToolStripMenuItem('Проверки и отчёты')
[void]$menu.Items.Add($setup);[void]$menu.Items.Add($diagnostics)
function MenuItem($parent,$text,$handler){$item=New-Object Windows.Forms.ToolStripMenuItem($text);$item.Add_Click($handler);[void]$parent.DropDownItems.Add($item);return $item}
$null=MenuItem $setup 'Сделать проверенный состав основным: служба + автозапуск + VPN-авто' {MenuAction InstallVerified}
$null=MenuItem $setup 'Применить черновик (без проверки)' {MenuAction Apply}
$null=MenuItem $setup 'Остановить MyZapret' {MenuAction Stop}
$null=MenuItem $setup 'Вернуть прежний zapret' {MenuAction Restore}
$null=MenuItem $diagnostics 'YouTube: проверить TCP / QUIC после отключения VPN' {StartControlTest}
$null=MenuItem $diagnostics 'Проверить все сервисы (VPN должен быть выключен)' {MenuAction TestMine @{Groups=@($BuilderCatalog.Keys)}}
$null=MenuItem $diagnostics 'Открыть последний отчёт TCP / QUIC' {
    $state=BRead "$BuilderDir/control-test.json"
    if($state.Report -and (Test-Path "$($state.Report)/table.html")){Start-Process "$($state.Report)/table.html"}else{Log 'Готового отчёта пока нет.'}
}
$null=MenuItem $diagnostics 'Показать состояние основной установки' {
    $svc=Get-Service $BuilderService -ErrorAction SilentlyContinue
    $old=Get-Service zapret -ErrorAction SilentlyContinue
    $auto=if($svc){(Get-ItemProperty "HKLM:/SYSTEM/CurrentControlSet/Services/$BuilderService").Start -eq 2}else{$false}
    $follow=BRead "$BuilderDir/vpn-follow.json"
    [void][Windows.Forms.MessageBox]::Show("Основная копия: $PackageRoot`r`nmyzapret2: $(if($svc){$svc.Status}else{'не установлена'})`r`nАвтозапуск: $auto`r`nVPN-авто: $($follow.Enabled)`r`nVPN: $(BVpnState)`r`nСтарая служба zapret: $(if($old){$old.Status}else{'не установлена'})",'Состояние MyZapret')
}
$form.MainMenuStrip=$menu;$form.Controls.Add($menu)

$null=MenuItem $diagnostics 'Discord: сравнить обработку голоса UDP после отключения VPN' {
    if((BRead "$BuilderDir/control-test.json").State -in @('Waiting','Running') -or (BRead "$BuilderDir/discord-voice-test.json").State -in @('Waiting','Running')){Log 'Проверка уже запущена.';return}
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$BuilderLab+'/discord-voice-test.ps1"')
    Log 'Оставьте Discord в голосовом канале. Проверка дождётся отключения VPN, сравнит три режима за три минуты и восстановит исходную стратегию.'
}
$null=MenuItem $diagnostics 'Discord: последний отчёт голоса UDP' {
    $state=BRead "$BuilderDir/discord-voice-test.json"
    if($state.Report -and (Test-Path "$($state.Report)/table.html")){Start-Process "$($state.Report)/table.html"}else{Log $state.Message}
}
$null=MenuItem $diagnostics 'Discord: отменить проверку голоса UDP' {[IO.File]::WriteAllText("$BuilderDir/discord-voice-cancel.flag",'cancel')}
$voiceMenu=New-Object Windows.Forms.ToolStripMenuItem('Голос Discord')
[void]$setup.DropDownItems.Add($voiceMenu)
$null=MenuItem $voiceMenu 'Включить постоянную обработку UDP (TTL4)' {MenuAction VoiceContinuous}
$null=MenuItem $voiceMenu 'Вернуть исходную обработку голоса' {MenuAction VoiceLegacy}
$null=MenuItem $setup 'Старый состав: исходный движок, служба и автозапуск' {MenuAction InstallLegacy}
$null=MenuItem $setup 'Вернуть предыдущий состав (также при включённом VPN)' {MenuAction PreviousPreset}
function StartCurrentCheck {
    param([switch]$ApplyDraft)
    if($script:job -or (BRead "$BuilderDir/current-check.json").State -in @('Waiting','Running') -or (BRead "$BuilderDir/control-test.json").State -in @('Waiting','Running') -or (BRead "$BuilderDir/discord-voice-test.json").State -in @('Waiting','Running')){Log 'Другая проверка уже выполняется.';return}
    $argsText='-NoProfile -ExecutionPolicy Bypass -File "'+$BuilderLab+'/check-current.ps1"'
    if($ApplyDraft){$argsText+=' -ApplyDraft'}
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList $argsText
    Log 'Проверка будет ждать отключения VPN. Оставайтесь в голосовом канале. По окончании откроется таблица.'
}
$null=MenuItem $diagnostics 'Проверить подключение: сервисы, видео и голос' {StartCurrentCheck}
$null=MenuItem $diagnostics 'Открыть последний отчёт текущего состава' {
    $state=BRead "$BuilderDir/current-check.json"
    if($state.Report -and (Test-Path "$($state.Report)/table.html")){Start-Process "$($state.Report)/table.html"}else{Log $state.Message}
}

$null=MenuItem $diagnostics 'Отменить общую проверку / ожидание VPN' {
    [IO.File]::WriteAllText("$BuilderDir/current-cancel.flag",'cancel')
    [IO.File]::WriteAllText("$BuilderDir/cancel.flag",'cancel')
    Log 'Отмена запрошена; дождитесь восстановления службы после проверки.'
}

$null=MenuItem $setup 'Discord как в обычном general.bat (старый движок)' {MenuAction InstallStockDiscord}

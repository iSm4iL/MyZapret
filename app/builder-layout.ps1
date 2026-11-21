# Reparent existing controls so all original actions keep their handlers.
$form.SuspendLayout()
$form.Text='MyZapret — подключение и стратегии'
$form.AutoScaleMode='Dpi';$form.AutoScaleDimensions=New-Object Drawing.SizeF(96,96)
$form.Font=New-Object Drawing.Font('Segoe UI',9)
$form.BackColor=[Drawing.ColorTranslator]::FromHtml('#F4F6F8')
$form.MinimumSize=New-Object Drawing.Size(1100,720)
function FindAction([string]$text){return @($script:buttons|Where-Object Text -eq $text|Select-Object -First 1)[0]}
function PlaceButton($parent,$button){
    if(-not $button){return}
    $button.Dock='None';$button.AutoSize=$false;$button.Size=New-Object Drawing.Size(190,36)
    $button.Margin=New-Object Windows.Forms.Padding(4);$button.FlatStyle='System'
    $parent.Controls.Add($button)
}
function LayoutTable([int]$rows){
    $t=New-Object Windows.Forms.TableLayoutPanel;$t.Dock='Fill';$t.ColumnCount=1;$t.RowCount=$rows
    $t.Margin=New-Object Windows.Forms.Padding(0);return $t
}
function ActionFlow($parent){
    $flow=New-Object Windows.Forms.FlowLayoutPanel;$flow.Dock='Fill';$flow.AutoScroll=$true
    $flow.Padding=New-Object Windows.Forms.Padding(8);$parent.Controls.Add($flow);return $flow
}
$applyButton=FindAction 'Применить черновик и запустить'
$applyButton.Visible=$false
$applyButton=$null
$stopButton=FindAction 'Стоп'
$returnButton=FindAction 'Откат применения';$returnButton.Text='Вернуть предыдущий состав'
# Preserve the existing rollback handler; a VPN-aware return is also in the menu.
$takeButton=@($bottom.Controls|Where-Object {$_ -is [Windows.Forms.Button]})[0]
$cancelButton=@($testControls.Controls|Where-Object Text -eq 'Отменить тест')[0]
$uiRoot.Controls.Clear();$uiRoot.RowStyles.Clear();$uiRoot.RowCount=4
foreach($style in @((New-Object Windows.Forms.RowStyle('Absolute',64)),(New-Object Windows.Forms.RowStyle('Absolute',48)),(New-Object Windows.Forms.RowStyle('Percent',100)),(New-Object Windows.Forms.RowStyle('Absolute',28)))){[void]$uiRoot.RowStyles.Add($style)}
$uiRoot.Padding=New-Object Windows.Forms.Padding(10,4,10,4)
$uiState.Dock='Fill';$uiState.Padding=New-Object Windows.Forms.Padding(8);$uiState.Font=New-Object Drawing.Font('Segoe UI',10)
$uiState.BackColor=[Drawing.Color]::White;$uiRoot.Controls.Add($uiState,0,0)
$bar=New-Object Windows.Forms.FlowLayoutPanel;$bar.Dock='Fill';$bar.WrapContents=$false
$applyButton=Button $bar 'Применить и проверить' 0 0 190 {StartCurrentCheck -ApplyDraft}
$checkButton=Button $bar 'Проверить подключение' 0 0 190 {StartCurrentCheck}
$bar.Controls.Remove($applyButton);$bar.Controls.Remove($checkButton)
PlaceButton $bar $checkButton;PlaceButton $bar $applyButton;PlaceButton $bar $stopButton
$modernButton=Button $bar 'Открыть конструктор' 0 0 190 {Run ModernDraft}
PlaceButton $bar $modernButton
$cancelAll=Button $bar 'Отменить проверку' 0 0 190 {
    foreach($flag in @('current-cancel.flag','control-cancel.flag','discord-voice-cancel.flag','cancel.flag')){[IO.File]::WriteAllText("$BuilderDir/$flag",'cancel')}
    Log 'Отмена запрошена. Дождитесь восстановления службы.'
} $false
PlaceButton $bar $cancelAll
$uiRoot.Controls.Add($bar,0,1)
$tabs=New-Object Windows.Forms.TabControl;$tabs.Dock='Fill';$tabs.Padding=New-Object Drawing.Point(14,7)
function NewPage([string]$title){$page=New-Object Windows.Forms.TabPage($title);$page.BackColor=[Drawing.Color]::White;$page.Padding=New-Object Windows.Forms.Padding(8);[void]$tabs.TabPages.Add($page);return $page}
$constructorPage=NewPage 'Сервисы и стратегии';$settingsPage=NewPage 'Настройки';$toolsPage=NewPage 'Диагностика';$logPage=NewPage 'Журнал'
$split.Panel1MinSize=0;$split.Panel2MinSize=0
$tabs.Size=New-Object Drawing.Size(1250,600);$constructorPage.Size=New-Object Drawing.Size(1230,550)
$constructorPage.Controls.Add($split);$split.Dock='Fill'
$split.SplitterDistance=570
foreach($panel in @($left,$right)){$panel.ColumnStyles.Clear();[void]$panel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))}
$left.RowStyles[0].Height=40;$left.RowStyles[1].Height=100;$left.RowStyles[3].Height=42
$right.RowStyles[0].Height=40;$right.RowStyles[1].Height=48;$right.RowStyles[3].Height=44
$testControls.Controls.Clear()
$scope=New-Object Windows.Forms.TableLayoutPanel;$scope.Dock='Fill';$scope.ColumnCount=2;$scope.RowCount=3
[void]$scope.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',90)));[void]$scope.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
foreach($height in @(30,30,40)){[void]$scope.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',$height)))}
$a=New-Object Windows.Forms.Label;$a.Text='Показать';$a.Dock='Fill';$a.TextAlign='MiddleLeft';$scope.Controls.Add($a,0,0)
$a=New-Object Windows.Forms.Label;$a.Text='Проверить';$a.Dock='Fill';$a.TextAlign='MiddleLeft';$scope.Controls.Add($a,0,1)
$category.Dock='Fill';$target.Dock='Fill';$scope.Controls.Add($category,1,0);$scope.Controls.Add($target,1,1)
$mineTest.Dock='Fill';$mineTest.Margin=New-Object Windows.Forms.Padding(0,3,0,3);$scope.Controls.Add($mineTest,0,2);$scope.SetColumnSpan($mineTest,2)
$testControls.Controls.Add($scope)
$donorControls.Controls.Clear();$donorTest.Dock='Fill';$donorTest.Margin=New-Object Windows.Forms.Padding(0,3,0,3);$donorControls.Controls.Add($donorTest)
$takeButton.Dock='Fill';$takeButton.Text='Взять выбранный сервис в черновик';$takeButton.Margin=New-Object Windows.Forms.Padding(0,4,0,0)
$donors.Columns[0].Frozen=$true;$donors.Columns[0].Width=175
foreach($grid in @($mine,$donors)){
    $grid.BackgroundColor=[Drawing.Color]::White;$grid.BorderStyle='FixedSingle';$grid.EnableHeadersVisualStyles=$false
    $grid.ColumnHeadersDefaultCellStyle.BackColor=[Drawing.ColorTranslator]::FromHtml('#E9EEF3');$grid.ColumnHeadersHeight=32
    $grid.DefaultCellStyle.Padding=New-Object Windows.Forms.Padding(4);$grid.RowTemplate.Height=28
    $grid.AlternatingRowsDefaultCellStyle.BackColor=[Drawing.ColorTranslator]::FromHtml('#F8FAFC')
}
$settings=New-Object Windows.Forms.TableLayoutPanel;$settings.Dock='Fill';$settings.ColumnCount=2;$settings.RowCount=1
foreach($x in @(50,50)){[void]$settings.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',$x)))}
$settingsPage.Controls.Add($settings)
$profile.Controls.Clear();$profile.Text='Черновик';$profile.Padding=New-Object Windows.Forms.Padding(12,24,12,12)
$formFields=New-Object Windows.Forms.TableLayoutPanel;$formFields.Dock='Top';$formFields.Height=200;$formFields.ColumnCount=2;$formFields.RowCount=5
[void]$formFields.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',80)));[void]$formFields.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
for($i=0;$i -lt 5;$i++){[void]$formFields.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',40)))}
$l=New-Object Windows.Forms.Label;$l.Text='Имя';$l.Dock='Fill';$l.TextAlign='MiddleLeft';$formFields.Controls.Add($l,0,0);$name.Dock='Fill';$formFields.Controls.Add($name,1,0)
$l=New-Object Windows.Forms.Label;$l.Text='База';$l.Dock='Fill';$l.TextAlign='MiddleLeft';$formFields.Controls.Add($l,0,1);$base.Dock='Fill';$formFields.Controls.Add($base,1,1)
foreach($pair in @(@('Сохранить имя',2),@('Сменить базу',3),@('Сбросить черновик',4))){$b=FindAction $pair[0];$b.Dock='Fill';$b.Margin=New-Object Windows.Forms.Padding(0,3,0,3);$formFields.Controls.Add($b,1,[int]$pair[1])}
$profile.Controls.Add($formFields);$profile.Dock='Fill';$settings.Controls.Add($profile,0,0)
$runtime.Controls.Clear();$runtime.Text='Служба и автоматический запуск';$runtime.Dock='Fill';$runtime.Padding=New-Object Windows.Forms.Padding(4,20,4,4)
$settings.Controls.Add($runtime,1,0);$flow=ActionFlow $runtime
foreach($text in @('Автостарт ВКЛ','Автостарт ВЫКЛ','Отключить старые zapret')){PlaceButton $flow (FindAction $text)}
PlaceButton $flow $followButton;PlaceButton $flow $returnButton
$legacyButton=Button $flow 'Discord: обычный zapret' 0 0 190 {Run InstallStockDiscord};PlaceButton $flow $legacyButton
$repairButton=Button $flow 'Восстановить перехват' 0 0 190 {Run RepairDriver};PlaceButton $flow $repairButton
$tools=ActionFlow $toolsPage
foreach($text in @('Диагностика YouTube / DNS','Тест YouTube: старый и новый движок','Подобрать решение YouTube (долго)','YouTube: TCP / QUIC после VPN','Ролик для теста…','Открыть видео','Отчёты','Инструкция','Папка MyZapret','Стратегии (JSON)')){PlaceButton $tools (FindAction $text)}
$game.Dock='None';$game.Width=360;$game.Height=30;$ipset.Dock='None';$ipset.Width=360;$ipset.Height=30
$tools.Controls.Add($game);$tools.SetFlowBreak($game,$true);$tools.Controls.Add($ipset);$tools.SetFlowBreak($ipset,$true)
foreach($text in @('Сохранить фильтры','Сброс Game + IPSet')){PlaceButton $tools (FindAction $text)}
$logPage.Controls.Add($uiLog);$uiLog.Font=New-Object Drawing.Font('Consolas',9)
$uiRoot.Controls.Add($tabs,0,2);$uiRoot.Controls.Add($footer,0,3)
$form.ResumeLayout($true)

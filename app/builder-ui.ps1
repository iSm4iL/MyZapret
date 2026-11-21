param([switch]$SelfTest,[switch]$AutoTest)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
if(-not $SelfTest -and -not $AutoTest){
    $installed=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\myzapret2\Parameters' -ErrorAction SilentlyContinue
    if($installed.MyZapretRoot -and [IO.Path]::GetFullPath([string]$installed.MyZapretRoot).TrimEnd('\') -ne [IO.Path]::GetFullPath((Split-Path $PSScriptRoot)).TrimEnd('\')){
        $panel=Join-Path $installed.MyZapretRoot 'app\builder-ui.ps1'
        if(Test-Path $panel){& $panel;return}
    }
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
. "$PSScriptRoot/builder-core.ps1"
. "$PSScriptRoot/grid-state.ps1"
BInitialize
$script:externalLastState=(BRead "$BuilderDir/repair-run.json").Time
$script:controlLastTime=(BRead "$BuilderDir/control-test.json").Time
$script:currentLastTime=(BRead "$BuilderDir/current-check.json").Time
$script:voiceLastTime=(BRead "$BuilderDir/discord-voice-test.json").Time
$script:job=$null;$script:nextRefresh=[datetime]::MinValue;$script:filtersDirty=$false;$script:loadingFilters=$false
$form=New-Object Windows.Forms.Form;$form.Text='MyZapret — полный конструктор / основная служба'
$form.ClientSize=New-Object Drawing.Size(1300,880);$form.MinimumSize=New-Object Drawing.Size(1050,650);$form.StartPosition='CenterScreen';$form.Font=New-Object Drawing.Font('Segoe UI',10)
$uiRoot=New-Object Windows.Forms.TableLayoutPanel;$uiRoot.Dock='Fill';$uiRoot.RowCount=4;$uiRoot.ColumnCount=1
foreach($s in @((New-Object Windows.Forms.RowStyle('Absolute',305)),(New-Object Windows.Forms.RowStyle('Percent',100)),(New-Object Windows.Forms.RowStyle('Absolute',100)),(New-Object Windows.Forms.RowStyle('Absolute',30)))){[void]$uiRoot.RowStyles.Add($s)}
$form.Controls.Add($uiRoot)
$top=New-Object Windows.Forms.TableLayoutPanel;$top.Dock='Fill';$top.RowCount=1;$top.ColumnCount=3
foreach($width in @(32,38,30)){[void]$top.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',$width)))};$uiRoot.Controls.Add($top,0,0)
function GroupBox($title,$column){$g=New-Object Windows.Forms.GroupBox;$g.Text=$title;$g.Dock='Fill';$top.Controls.Add($g,$column,0);return $g}
$profile=GroupBox '1. Состав черновика' 0;$runtime=GroupBox '2. Запуск и автозагрузка' 1;$filters=GroupBox '3. Игровые фильтры и инструменты' 2
function Label($p,$text,$x,$y,$w,$h=25){$l=New-Object Windows.Forms.Label;$l.Text=$text;$l.SetBounds($x,$y,$w,$h);$p.Controls.Add($l);return $l}
$script:buttons=New-Object Collections.Generic.List[Windows.Forms.Button]
function Button($p,$text,$x,$y,$w,$handler,[bool]$BusyDisable=$true){$b=New-Object Windows.Forms.Button;$b.Text=$text;$b.SetBounds($x,$y,$w,42);$b.Add_Click($handler);$p.Controls.Add($b);if($BusyDisable){$script:buttons.Add($b)};return $b}
function Combo($p,$x,$y,$w,$values){$c=New-Object Windows.Forms.ComboBox;$c.SetBounds($x,$y,$w,28);$c.DropDownStyle='DropDownList';foreach($v in $values){[void]$c.Items.Add($v)};$c.SelectedIndex=0;$p.Controls.Add($c);return $c}
$null=Label $profile 'Имя:' 10 27 50
$name=New-Object Windows.Forms.TextBox;$name.SetBounds(65,23,180,28);$profile.Controls.Add($name)
$null=Label $profile 'База:' 10 65 50
$base=Combo $profile 65 61 330 (@('Старый состав (исходный winws)')+@(Get-Configs))
$uiState=Label $runtime '' 10 25 460 57
$game=New-Object Windows.Forms.CheckBox;$game.Text='Game Filter: дополнительные порты';$game.SetBounds(10,26,355,28);$filters.Controls.Add($game)
$ipset=New-Object Windows.Forms.CheckBox;$ipset.Text='IPSet loaded: список сетей для обхода';$ipset.SetBounds(10,55,355,28);$filters.Controls.Add($ipset)
$split=New-Object Windows.Forms.SplitContainer;$split.Size=New-Object Drawing.Size(1280,500);$split.Dock='Fill';$split.SplitterDistance=570;$split.Panel1MinSize=430;$split.Panel2MinSize=450;$uiRoot.Controls.Add($split,0,1)
function Grid {$g=New-Object Windows.Forms.DataGridView;$g.Dock='Fill';$g.ReadOnly=$true;$g.AllowUserToAddRows=$false;$g.AllowUserToDeleteRows=$false;$g.RowHeadersVisible=$false;$g.MultiSelect=$false;return $g}
$left=New-Object Windows.Forms.TableLayoutPanel;$left.Dock='Fill';$left.RowCount=4;$left.ColumnCount=1
foreach($s in @((New-Object Windows.Forms.RowStyle('Absolute',43)),(New-Object Windows.Forms.RowStyle('Absolute',100)),(New-Object Windows.Forms.RowStyle('Percent',100)),(New-Object Windows.Forms.RowStyle('Absolute',43)))){[void]$left.RowStyles.Add($s)};$split.Panel1.Controls.Add($left)
$title=New-Object Windows.Forms.Label;$title.Dock='Fill';$title.Text="МОЙ ALT: черновик / активный состав`r`nТесты временны. После выбора донора нажмите «Применить».";$left.Controls.Add($title,0,0)
$testControls=New-Object Windows.Forms.Panel;$testControls.Dock='Fill';$left.Controls.Add($testControls,0,1)
$null=Label $testControls 'Показать:' 5 6 75
$category=Combo $testControls 80 3 150 @('Все','Основные','Игровые платформы','AI')
$null=Label $testControls 'Проверить:' 240 6 85
$target=Combo $testControls 330 3 220 (@('Все сервисы (17)','Показанный раздел')+@($BuilderCatalog.Keys|ForEach-Object {$BuilderCatalog[$_].Label}))
$mine=Grid;$mine.AutoSizeColumnsMode='Fill';$mine.AutoSizeRowsMode='AllCells'
foreach($c in @('Сервис','Черновик','Активный','Проверка')){[void]$mine.Columns.Add($c,$c)};$left.Controls.Add($mine,0,2)
$mine.Columns[3].DefaultCellStyle.WrapMode='True'
$mineNote=New-Object Windows.Forms.Label;$mineNote.Dock='Fill';$left.Controls.Add($mineNote,0,3)
$right=New-Object Windows.Forms.TableLayoutPanel;$right.Dock='Fill';$right.RowCount=4;$right.ColumnCount=1
foreach($s in @((New-Object Windows.Forms.RowStyle('Absolute',43)),(New-Object Windows.Forms.RowStyle('Absolute',40)),(New-Object Windows.Forms.RowStyle('Percent',100)),(New-Object Windows.Forms.RowStyle('Absolute',43)))){[void]$right.RowStyles.Add($s)};$split.Panel2.Controls.Add($right)
$title=New-Object Windows.Forms.Label;$title.Dock='Fill';$title.Text="ДОНОРЫ: выберите ячейку нужного сервиса`r`nПрокрутка вправо показывает остальные сервисы выбранного раздела.";$right.Controls.Add($title,0,0)
$donorControls=New-Object Windows.Forms.Panel;$donorControls.Dock='Fill';$right.Controls.Add($donorControls,0,1)
$donors=Grid;$donors.AutoSizeColumnsMode='None';$donors.AutoSizeRowsMode='AllCells';$donors.SelectionMode='CellSelect';[void]$donors.Columns.Add('Donor','ALT-донор');$donors.Columns[0].Width=235
foreach($group in $BuilderCatalog.Keys){[void]$donors.Columns.Add($group,$BuilderCatalog[$group].Label);$donors.Columns[$group].Width=155};$right.Controls.Add($donors,0,2)
$donors.Columns['youtube'].Width=255;$donors.Columns['youtube'].DefaultCellStyle.WrapMode='True'
$bottom=New-Object Windows.Forms.Panel;$bottom.Dock='Fill';$right.Controls.Add($bottom,0,3)
$uiLog=New-Object Windows.Forms.TextBox;$uiLog.Dock='Fill';$uiLog.ReadOnly=$true;$uiLog.Multiline=$true;$uiLog.ScrollBars='Vertical';$uiRoot.Controls.Add($uiLog,0,2)
$footer=New-Object Windows.Forms.Label;$footer.Dock='Fill';$uiRoot.Controls.Add($footer,0,3)
function Log($text){$uiLog.AppendText("$text`r`n")}
function VisibleGroups {return @($BuilderCatalog.Keys|Where-Object {$category.SelectedItem -eq 'Все' -or $BuilderCatalog[$_].Category -eq [string]$category.SelectedItem})}
function TestGroups {
    if($target.SelectedIndex -eq 0){return @($BuilderCatalog.Keys)}
    if($target.SelectedIndex -eq 1){return @(VisibleGroups)}
    return @($BuilderCatalog.Keys|Where-Object {$BuilderCatalog[$_].Label -eq [string]$target.SelectedItem})
}
function TestScope {
    $groups=@(TestGroups)
    if($groups.Count -eq $BuilderCatalog.Count){return "все $($groups.Count) сервисов"}
    if($groups.Count -eq 1){return [string]$BuilderCatalog[$groups[0]].Label}
    return "$($category.SelectedItem): $($groups.Count) серв."
}
function UpdateTestButtons {
    $mineTest.Text='Проверить черновик: '+(TestScope)
    $donorTest.Text='Сравнить стратегии: '+(TestScope)
}
function Run([string]$action,$data=$null){
    if($script:job){Log 'Дождитесь операции или отмените тест.';return}
    if((BRead "$BuilderDir/current-check.json").State -eq 'Running'){Log 'Общая проверка ещё выполняется; дождитесь или отмените её через меню.';return}
    if((BRead "$BuilderDir/discord-voice-test.json").State -eq 'Running'){Log 'Выполняется проверка голоса Discord. Дождитесь окончания.';return}
    if($action -in @('TestMine','TestDonors')){
        $labels=@($data.Groups|ForEach-Object {$BuilderCatalog[$_].Label})
        Log ("Будут проверены ($($labels.Count)): "+($labels -join ', '))
    }
    $file=Join-Path $BuilderDir ('request-'+[guid]::NewGuid().ToString('N')+'.json')
    if($data){BSave $data $file}
    $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$BuilderLab+'/builder-job.ps1" -Action '+$action
    if($data){$arguments+=' -RequestFile "'+$file+'"'}
    $script:job=Start-Process powershell.exe -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput "$BuilderDir/ui-output.txt" -RedirectStandardError "$BuilderDir/ui-error.txt"
    $null=$script:job.Handle
    $script:action=$action
    foreach($b in $script:buttons){$b.Enabled=$false}
    $category.Enabled=$false;$target.Enabled=$false
    Log "Начато: $action. Тесты и применение выполняются без VPN."
}
function Source($m,$g){if(-not $m){return 'Не применён'};if($m.Engine -eq 'winws'){return 'Точный старый состав'};$map=BSelections $m;if($map.Contains($g)){$e=$map[$g];return $(if($e -is [string]){$e}else{$e.Config})};return 'Из базы'}
function Refresh {
    if((Get-Date) -lt $script:nextRefresh){return};$script:nextRefresh=(Get-Date).AddSeconds(2)
    $mineView=BGridState $mine;$donorView=BGridState $donors
    try{
        $m=BRead $BuilderDraft;$a=BRead $BuilderActive;$r=BRead "$BuilderDir/mine-results.json";$data=BRead "$BuilderDir/donor-results.json"
        $hash=BHash (BBuild $m);$baseHash=BBaseHash $m
        $svc=Get-Service $BuilderService -ErrorAction SilentlyContinue
        $auto=if($svc){(Get-ItemProperty "HKLM:/SYSTEM/CurrentControlSet/Services/$BuilderService").Start -eq 2}else{$false}
        $serviceText=if(-not $svc){'не установлена'}elseif($svc.Status -eq 'Running'){'работает'}elseif($svc.Status -eq 'Stopped' -and (BVpnState) -eq 'On'){'пауза при включённом VPN'}elseif($svc.Status -eq 'Stopped'){'остановлена'}else{[string]$svc.Status}
        $uiState.Text="Применён: $(if($a){$a.Model.Name}else{'нет'}) | Служба: $serviceText`r`nАвтостарт: $(if($auto){'ВКЛ'}else{'ВЫКЛ'}) | VPN: $(if(Vpn-Connected){'ВКЛ'}else{'ВЫКЛ'}) | Черновик: $(if($a -and $a.ModelHash -eq $hash){'как активный'}else{'изменён / не применён'})"
        $follow=BRead "$BuilderDir/vpn-follow.json"
        $followButton.Text='VPN-авто: '+$(if($follow.Enabled){'ВКЛ'}else{'ВЫКЛ'})
        if(-not $name.Focused){$name.Text=$m.Name}
        if(-not $script:filtersDirty){$script:loadingFilters=$true;try{$game.Checked=[bool]$m.GameFilter;$ipset.Checked=[bool]$m.IpsetLoaded}finally{$script:loadingFilters=$false}}
        $groups=@(VisibleGroups);BGridRows $mine $groups;$i=-1
        foreach($g in $groups){
            $row=@($r.Rows|Where-Object {$_.Group -eq $g}|Select-Object -Last 1);$fresh=$r -and $r.ModelHash -eq $hash -and $r.ProbeHash -eq (BProbeHash)
            $text=if(-not $row.Count){'Не проверено'}elseif(-not $fresh){'Другой состав'}else{"$($row[0].Passed)/$($row[0].Total) страниц"}
            $i++;$values=@($BuilderCatalog[$g].Label,(Source $m $g),(Source $(if($a){$a.Model}else{$null}) $g),$text)
            for($c=0;$c -lt $values.Count;$c++){if($mine.Rows[$i].Cells[$c].Value -ne $values[$c]){$mine.Rows[$i].Cells[$c].Value=$values[$c]}}
            if(-not($fresh -and $row.Count)){$mine.Rows[$i].Cells[3].Style.BackColor=[Drawing.Color]::White;$mine.Rows[$i].Cells[3].ToolTipText='Не проверено для текущего состава'}
            if($g -eq 'discord' -and $fresh -and $row.Count){
                $voiceResult=BRead "$BuilderDir/voice-result.json"
                $voiceFresh=$a -and $voiceResult.SourceHash -eq (BHash $a.ServiceImage)
                $voiceText=if(-not $voiceFresh){'голос не проверен'}elseif($voiceResult.Timeouts -gt 0){"ГОЛОС: потери ($($voiceResult.Timeouts))"}elseif($voiceResult.Replies -ge 6){'ping стабилен; звук не подтверждён'}else{'голос не подтверждён'}
                $mine.Rows[$i].Cells[3].Value+=' / '+$voiceText
            };if($g -eq 'youtube' -and $fresh -and $row.Count){$mine.Rows[$i].Cells[3].Value+=$(if($row[0].VideoChecked){if($row[0].VideoPass){' / CDN OK'}else{' / CDN сбой'}}else{' / видео не проверено'})};if($fresh -and $row.Count){$mine.Rows[$i].Cells[3].Style.BackColor=if($row[0].Pass -and ($g -ne 'youtube' -or $row[0].VideoChecked)){[Drawing.Color]::Honeydew}else{[Drawing.Color]::LemonChiffon};$mine.Rows[$i].Cells[3].ToolTipText=$row[0].Details}
        }
        foreach($g in $BuilderCatalog.Keys){$donors.Columns[$g].Visible=$g -in $groups}
        $donorNames=@(Get-Configs);BGridRows $donors $donorNames;$index=-1
        foreach($donor in $donorNames){
            $index++;$donors.Rows[$index].Cells[0].Value=$donor
            foreach($g in $BuilderCatalog.Keys){
                $cell=$donors.Rows[$index].Cells[$g];$row=@($data.Rows|Where-Object {$_.Donor -eq $donor -and $_.Group -eq $g}|Select-Object -Last 1)
                if(-not $row.Count){$cell.Value='—';$cell.Style.BackColor=[Drawing.Color]::White;$cell.ToolTipText='Не проверено';continue}
                $fresh=$data.ProbeHash -eq (BProbeHash) -and $data.BaseHash -eq $baseHash -and $row[0].Total -eq $BuilderProbeGroups[$g].Count
                $cell.Value=if($fresh){"$($row[0].Passed)/$($row[0].Total) страниц"}else{'Нужен новый тест'}
                if($g -eq 'youtube' -and $fresh){$cell.Value+=$(if($row[0].VideoChecked){if($row[0].VideoPass){' / CDN OK'}else{' / CDN сбой'}}else{' / видео не проверено'})};
                $cell.Style.BackColor=if(-not $fresh){[Drawing.Color]::LightGray}elseif($row[0].Pass -and ($g -ne 'youtube' -or $row[0].VideoChecked)){[Drawing.Color]::Honeydew}else{[Drawing.Color]::LemonChiffon}
                $cell.ToolTipText="$($cell.Value)`r`n$($row[0].Time)`r`n$($row[0].Details)"
            }
        }
        $lastTime=(@($r.Rows|Sort-Object Time -Descending|Select-Object -First 1)).Time
        $mineNote.Text="Черновик: $($m.BaseName). Последняя проверка: $lastTime`r`nЗелёный цвет относится к тому тесту, а не к текущему соединению."
        $external=BRead "$BuilderDir/repair-run.json"
        $externalActive=$external.State -eq 'Running' -and [bool](Get-Process -Id ([int]$external.PID) -ErrorAction SilentlyContinue)
        if($external.State -in @('Complete','Failed') -and $script:externalLastState -ne $external.Time){
            $script:externalLastState=$external.Time
            Log ('Фоновое восстановление: '+$external.Message)
            Log ((Get-Content "$PackageRoot/reports/full-repair-run.log" -Tail 14 -Encoding UTF8 -ErrorAction SilentlyContinue) -join "`r`n")
        }
        if(-not $script:job){foreach($button in $script:buttons){$button.Enabled=-not $externalActive};$category.Enabled=-not $externalActive;$target.Enabled=-not $externalActive}
        $control=BRead "$BuilderDir/control-test.json"
        if($control -and $script:controlLastTime -ne $control.Time){$script:controlLastTime=$control.Time;Log ("Контроль YouTube: "+$control.Message+" Отчёт: "+$control.Report)}
        if($control.State -in @('Waiting','Running')){
            if($control.State -eq 'Running'){foreach($button in $script:buttons){$button.Enabled=$false}}
        }
        $p=BRead "$BuilderDir/progress.json"
        $footer.Text=if(($script:job -or $externalActive) -and $p){"$($p.Index)/$($p.Total): $($p.Donor) — $($p.Stage). После теста прежний запуск восстанавливается."}elseif($script:job){"Выполняется $script:action..."}else{'YouTube: проверяется получение видеофрагмента. Полный плеер, голос и игровые серверы — отдельные проверки.'}
        if($control.State -in @('Waiting','Running')){$footer.Text='Контроль YouTube: '+$control.Message}
        $current=BRead "$BuilderDir/current-check.json"
        if($current.State -in @('Waiting','Running')){$footer.Text=$current.Message}
        if($current -and $script:currentLastTime -ne $current.Time){$script:currentLastTime=$current.Time;Log $current.Message}
        if($modernButton){
            $legacy=$m.Engine -eq 'winws'
            $modernButton.Visible=$legacy
            $busy=$script:job -or $externalActive -or $current.State -eq 'Running' -or $control.State -eq 'Running'
            $donorTest.Enabled=-not $legacy -and -not $busy
            $takeButton.Enabled=-not $legacy -and -not $busy
            $game.Enabled=-not $legacy -and -not $busy;$ipset.Enabled=-not $legacy -and -not $busy
            if($legacy){$donorTest.Text='Для доноров нажмите «Открыть конструктор»'}
        }
        $voice=BRead "$BuilderDir/discord-voice-test.json"
        if($voice.State -in @('Waiting','Running')){$footer.Text='Discord: '+$voice.Message}
        if($voice -and $script:voiceLastTime -ne $voice.Time){$script:voiceLastTime=$voice.Time;Log ('Discord: '+$voice.Message)}
    }catch{$footer.Text=$_.Exception.Message}
    finally{BRestoreGrid $mine $mineView;BRestoreGrid $donors $donorView}
}
$null=Button $profile 'Сохранить имя' 253 22 140 {Run Rename @{Name=$name.Text}}
$null=Button $profile 'Сменить базу' 10 100 145 {if([string]$base.SelectedItem -eq 'Старый состав (исходный winws)'){Log 'Для выбора старого состава используйте меню «Настройка → Старый состав». Для черновика winws2 выберите другую базу.'}else{Run Base @{Donor=[string]$base.SelectedItem}}}
$null=Button $profile 'Сбросить черновик' 165 100 225 {Run ResetDraft}
$null=Label $profile 'Переносы и фильтры сначала меняют только черновик.' 10 140 380 30
$null=Button $profile 'Стратегии (JSON)' 10 175 175 {Start-Process explorer.exe -ArgumentList "$PackageRoot/strategies"}
$null=Button $profile 'Папка MyZapret' 200 175 190 {Start-Process explorer.exe -ArgumentList $PackageRoot}
$null=Button $runtime 'Применить черновик и запустить' 10 85 190 {if($script:filtersDirty){Log 'Сначала нажмите «Сохранить фильтры», затем примените ALT.'}else{Run Apply}}
$null=Button $runtime 'Стоп' 210 85 80 {Run Stop}
$null=Button $runtime 'Откат применения' 300 85 165 {Run PreviousPreset}
$null=Button $runtime 'Автостарт ВКЛ' 10 125 140 {Run AutoOn}
$null=Button $runtime 'Автостарт ВЫКЛ' 160 125 140 {Run AutoOff}
$null=Button $runtime 'Вернуть прежний zapret' 310 125 155 {Run Restore}
$null=Button $runtime 'Подобрать решение YouTube (долго)' 10 250 450 {Run RepairAll}
$null=Button $runtime 'Тест YouTube: старый и новый движок' 10 210 450 {Run CompareYouTube}
$null=Button $runtime 'Отключить старые zapret' 10 170 280 {Run DisableOld}
$followButton=Button $runtime 'VPN-авто' 300 170 165 {if((BRead "$BuilderDir/vpn-follow.json").Enabled){Run FollowOff}else{Run FollowOn}}
$null=Button $filters 'Сохранить фильтры' 10 90 160 {Run Filters @{GameFilter=$game.Checked;IpsetLoaded=$ipset.Checked}}
$null=Button $filters 'Сброс Game + IPSet' 180 90 180 {Run ResetFilters}
$null=Button $filters 'Старый движок' 10 130 140 {Start-Process powershell.exe -ArgumentList @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',"$PackageRoot/../zapret2-lab/builder-panel.ps1") -WindowStyle Hidden}
$null=Button $filters 'Инструкция' 160 130 100 {Start-Process notepad.exe -ArgumentList "$PackageRoot/README-RU.txt"}
$null=Button $filters 'Отчёты' 270 130 90 {Start-Process explorer.exe -ArgumentList "$PackageRoot/reports"}
$null=Button $filters 'Диагностика YouTube / DNS' 10 210 350 {Run DnsCheck}
$null=Button $filters 'YouTube через локальный TLS' 10 250 350 {Start-Process powershell.exe -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$BuilderLab+'/open-local-youtube.ps1"')}
$null=Button $filters 'Ролик для теста…' 10 170 210 {
    $dialog=New-Object Windows.Forms.Form;$dialog.Text='Автоматическая проверка видео YouTube';$dialog.Size=New-Object Drawing.Size(760,260);$dialog.StartPosition='CenterParent'
    $hint=New-Object Windows.Forms.Label;$hint.Text="Видео проверяется автоматически вместе с YouTube для каждой стратегии.`r`nПо умолчанию используется открытый ролик Big Buck Bunny.`r`nМожно вставить обычную ссылку YouTube на другой открытый ролик.`r`nПустое поле возвращает тестовый ролик. Искать googlevideo-ссылку больше не нужно.";$hint.SetBounds(10,10,720,90);$dialog.Controls.Add($hint)
    $input=New-Object Windows.Forms.TextBox;$input.SetBounds(10,110,720,28);$v=BVideoSettings;$input.Text=$(if($v.Url){[string]$v.Url}else{[string]$v.WatchUrl});$dialog.Controls.Add($input)
    $ok=New-Object Windows.Forms.Button;$ok.Text='Сохранить';$ok.SetBounds(10,155,130,32);$ok.DialogResult='OK';$dialog.Controls.Add($ok);$dialog.AcceptButton=$ok
    if($dialog.ShowDialog($form) -eq 'OK'){Run VideoUrl @{Url=$input.Text.Trim()}};$dialog.Dispose()
}
$null=Button $filters 'Открыть видео' 230 170 130 {Start-Process (BWatchUrl ([string](BVideoSettings).WatchUrl))}
$mineTest=Button $testControls '' 5 36 360 {Run TestMine @{Groups=@(TestGroups)}}
$null=Button $testControls 'Отменить тест' 375 36 175 {if((BRead "$BuilderDir/control-test.json").State -in @('Waiting','Running')){[IO.File]::WriteAllText("$BuilderDir/control-cancel.flag",'cancel');[IO.File]::WriteAllText("$BuilderDir/cancel.flag",'cancel')};if($script:action -in @('TestMine','TestDonors','CompareYouTube','RepairAll') -or (BRead "$BuilderDir/repair-run.json").State -eq 'Running'){[IO.File]::WriteAllText("$BuilderDir/cancel.flag",'cancel')}} $false
$donorTest=Button $donorControls '' 5 3 430 {Run TestDonors @{Groups=@(TestGroups)}}
$null=Button $bottom '← Взять выбранный сервис в черновик' 5 3 390 {
    if(-not $donors.SelectedCells.Count){return};$cell=$donors.SelectedCells[0];$g=$donors.Columns[$cell.ColumnIndex].Name
    if(-not $BuilderCatalog.Contains($g)){Log 'Выберите ячейку сервиса, не имя ALT.';return}
    Run Take @{Group=$g;Donor=[string]$donors.Rows[$cell.RowIndex].Cells[0].Value}
}
$category.Add_SelectedIndexChanged({UpdateTestButtons;$script:nextRefresh=[datetime]::MinValue;Refresh})
$target.Add_SelectedIndexChanged({UpdateTestButtons})
UpdateTestButtons
$game.Add_CheckedChanged({if(-not $script:loadingFilters){$script:filtersDirty=$true;if($game.Checked){$ipset.Checked=$true}}})
$ipset.Add_CheckedChanged({if(-not $script:loadingFilters){$script:filtersDirty=$true}})
$timer=New-Object Windows.Forms.Timer;$timer.Interval=750
$timer.Add_Tick({
    if($script:job -and $script:job.HasExited){
        $script:job.WaitForExit();if($script:job.ExitCode -ne 0){$tabs.SelectedTab=$logPage};Log (Get-Content "$BuilderDir/ui-output.txt" -Raw -Encoding UTF8 -ErrorAction SilentlyContinue);Log (Get-Content "$BuilderDir/ui-error.txt" -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)
        Log $(if($script:job.ExitCode -ne 0){'Действие не выполнено. Причина приведена выше.'}elseif($script:action -in @('TestMine','TestDonors','DnsCheck','CompareYouTube','RepairAll')){'ПРОВЕРКА ЗАВЕРШЕНА. Работоспособность смотрите по результатам, а не по факту завершения.'}else{'УСПЕШНО: '+$script:action})
        if($script:job.ExitCode -eq 0 -and $script:action -in @('Filters','ResetFilters','ResetDraft')){$script:filtersDirty=$false}
        if($script:job.ExitCode -eq 0 -and $script:action -in @('ModernDraft','Base','ResetDraft')){
            $d=BRead $BuilderDraft
            $value=if($d.Engine -eq 'winws'){'Старый состав (исходный winws)'}else{[string]$d.BaseName}
            if($base.Items.Contains($value)){$base.SelectedItem=$value}
        }
        $script:job.Dispose();$script:job=$null;foreach($b in $script:buttons){$b.Enabled=$true};$script:nextRefresh=[datetime]::MinValue
        $category.Enabled=$true;$target.Enabled=$true
    }
    Refresh
})
$form.Add_FormClosing({param($sender,$e);if($script:job){$e.Cancel=$true;Log 'Дождитесь завершения. Для теста используйте отмену.'}})
$form.Add_FormClosed({$timer.Stop();$timer.Dispose()})
$m=BRead $BuilderDraft;if($m.Engine -eq 'winws'){$base.SelectedItem='Старый состав (исходный winws)'};$baseName=([string]$m.BaseName)-replace ' \(снимок текущего состава\)$','';if($base.Items.Contains($baseName)){$base.SelectedItem=$baseName}
Log 'Проверка подключения ждёт отключения VPN. У Discord сайт и голос проверяются отдельно; работа сайта не подтверждает голос.'
Refresh
$null=Button $runtime 'YouTube: TCP / QUIC после VPN' 10 290 450 {
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$BuilderLab+'/youtube-control-test.ps1" -TransportMatrix')
    Log 'Фоновый тест ждёт отключения VPN до 60 минут. Сравнит два ролика и восстановит прежний запуск. Результат: data/control-test.json и reports/YouTube-Control-*.'
}
. "$BuilderLab/builder-layout.ps1"
$tips=New-Object Windows.Forms.ToolTip;$tips.AutoPopDelay=20000
foreach($button in $script:buttons){$tips.SetToolTip($button,$button.Text)}
$form.Add_Shown({$callback=Get-Variable LauncherReady -ValueOnly -ErrorAction SilentlyContinue;if($callback){$callback.Invoke()}})

. "$BuilderLab/builder-menu.ps1"
if($SelfTest){
    if(@(TestGroups).Count -ne $BuilderCatalog.Count){throw 'Default scan must include all services'}
    $category.SelectedItem='AI'
    if(@(TestGroups).Count -ne $BuilderCatalog.Count){throw 'Display filter unexpectedly limited all-service scan'}
    $target.SelectedIndex=1
    if(@(TestGroups).Count -ne 2){throw 'Visible category scan did not select AI services'}
    $target.SelectedItem='Spotify'
    if(@(TestGroups).Count -ne 1 -or @(TestGroups)[0] -ne 'spotify'){throw 'Single-service scan failed'}
    $category.SelectedIndex=0;$target.SelectedIndex=0;$script:nextRefresh=[datetime]::MinValue;Refresh
    if($mine.Rows.Count -ne $BuilderCatalog.Count -or $donors.Columns.Count -ne $BuilderCatalog.Count+1){throw 'Catalog not represented in tables'}
    'PASS: grouped UI, full catalog, category filtering, selected-service scans, game/IPSet controls.'
    $form.ShowInTaskbar=$false;$form.StartPosition='Manual';$form.Location=New-Object Drawing.Point(-32000,-32000);$form.Show();[Windows.Forms.Application]::DoEvents()
    $mine.CurrentCell=$mine.Rows[14].Cells[1];$mine.FirstDisplayedScrollingRowIndex=5
    $donors.CurrentCell=$donors.Rows[8].Cells['spotify'];$donors.FirstDisplayedScrollingRowIndex=2;$donors.HorizontalScrollingOffset=400
    $leftBefore=BGridState $mine;$rightBefore=BGridState $donors;$sameRow=$donors.Rows[0]
    for($cycle=0;$cycle -lt 3;$cycle++){$script:nextRefresh=[datetime]::MinValue;Refresh;[Windows.Forms.Application]::DoEvents()}
    $leftAfter=BGridState $mine;$rightAfter=BGridState $donors
    foreach($property in @('Row','Column','Top','Horizontal')){
        if($leftBefore.$property -ne $leftAfter.$property -or $rightBefore.$property -ne $rightAfter.$property){throw "Grid position changed after refresh: $property"}
    }
    if(-not [object]::ReferenceEquals($sameRow,$donors.Rows[0])){throw 'Refresh recreated existing rows'}
    'PASS: both grids retain selection, vertical/horizontal scroll and existing row objects across timer refreshes.'
    $bmp=New-Object Drawing.Bitmap($form.Width,$form.Height)
    try{$form.DrawToBitmap($bmp,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)));$bmp.Save("$BuilderDir/ui-preview.png",[Drawing.Imaging.ImageFormat]::Png)}finally{$bmp.Dispose();$form.Hide()}
    function SaveLayoutPreview([string]$file){
        [Windows.Forms.Application]::DoEvents()
        $bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height)
        try{$form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)));$bitmap.Save("$BuilderDir/$file",[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
    }
    $form.Show()
    foreach($page in @($settingsPage,$toolsPage)){$tabs.SelectedTab=$page;SaveLayoutPreview $(if($page -eq $settingsPage){'ui-settings.png'}else{'ui-diagnostics.png'})}
    $tabs.SelectedTab=$constructorPage;$form.ClientSize=New-Object Drawing.Size(1100,720)
    [Windows.Forms.Application]::DoEvents()
    foreach($b in $bar.Controls){if($b.Visible -and ($b.Right -gt $bar.ClientSize.Width -or $b.Bottom -gt $bar.ClientSize.Height)){throw ('Toolbar clipped: '+$b.Text)}}
    SaveLayoutPreview 'ui-compact.png'
    $form.ClientSize=New-Object Drawing.Size(1300,880);$form.Scale((New-Object Drawing.SizeF(1.25,1.25)))
    SaveLayoutPreview 'ui-125.png'
    'PASS: main actions fit compact window; settings and diagnostics rendered; 125% scaled preview saved.'
    $form.Hide();$timer.Dispose();$form.Dispose();return
}
if($AutoTest){$form.Add_Shown({Run TestDonors @{Groups=@(TestGroups)}})}
$timer.Start();[void]$form.ShowDialog()

function EnginePath($command){
 $m=[regex]::Match([string]$command,'^\s*(?:"([^"]+)"|(\S+))')
 if(-not $m.Success){return $null}
 $path=if($m.Groups[1].Success){$m.Groups[1].Value}else{$m.Groups[2].Value}
 try{if([IO.Path]::GetFileName($path) -notin @('winws.exe','winws2.exe')){return $null}}catch{return $null}
 return $path
}
function TaskSignature($task){return (@($task.Actions|ForEach-Object {$_.Execute+'|'+$_.Arguments+'|'+$_.WorkingDirectory}) -join "`n")}
function ServiceImage($service){
 if($service.PathName){return [string]$service.PathName}
 return [string](Get-ItemProperty "HKLM:/SYSTEM/CurrentControlSet/Services/$($service.Name)" -ErrorAction SilentlyContinue).ImagePath
}
function FindOtherZapret {
 $allServices=@(Get-CimInstance Win32_Service)
 $services=@(foreach($s in $allServices){
  $image=ServiceImage $s
  if($s.Name -eq $ServiceName -or -not(EnginePath $image)){continue}
  $reg=Get-ItemProperty "HKLM:/SYSTEM/CurrentControlSet/Services/$($s.Name)"
  [pscustomobject]@{Name=$s.Name;Image=$image;Start=[int]$reg.Start;Delayed=[int]$reg.DelayedAutoStart;Running=((Get-Service $s.Name).Status -eq 'Running')}
 })
 $tasks=@(foreach($task in @(Get-ScheduledTask)){
  if($task.TaskName -eq $TaskName){continue}
  $direct=@($task.Actions|Where-Object {$_.Execute -and (EnginePath ('"'+([string]$_.Execute).Trim('"')+'"'))}).Count -gt 0
  $known=$task.TaskName -match '^(zapret-(auto-mode|vpn-switch|best-test)|MyZapret-(VPN-follow|YouTube-repair|MSS-transport|NoSNI-test|YouTube-cdn|YouTube-trace))$'
  $script=($task.Actions.Arguments -join ' ') -match '(?i)(zapret_auto|vpn_zapret_switch|vpn-watch|run-full-repair|test-mss-transport|test-no-sni|check-youtube-cdn|trace-youtube|run_best)\.ps1(?:"|\s|$)'
  if($direct -or ($known -and $script)){
   [pscustomobject]@{Name=$task.TaskName;Path=$task.TaskPath;Enabled=[bool]$task.Settings.Enabled;Running=([string]$task.State -eq 'Running');Signature=(TaskSignature $task)}
  }
 })
 $servicePids=@($allServices|Where-Object ProcessId|ForEach-Object {[int]$_.ProcessId})
 $processes=@(foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='winws.exe' OR Name='winws2.exe'")){
  if([int]$p.ProcessId -in $servicePids){continue}
  if(-not $p.ExecutablePath -or -not(EnginePath ('"'+$p.ExecutablePath+'"')) -or -not $p.CommandLine){throw 'Не удалось определить путь отдельного winws. Закройте его окно вручную.'}
  [pscustomobject]@{Id=[int]$p.ProcessId;Created=([datetime]$p.CreationDate).ToString('o');File=$p.ExecutablePath;Command=$p.CommandLine;Hash=(Get-FileHash -LiteralPath $p.ExecutablePath -Algorithm SHA256).Hash;Restored=$false}
 })
 return [pscustomobject]@{Services=$services;Tasks=$tasks;Processes=$processes;Time=(Get-Date).ToString('s')}
}
function SameProcess($p,$saved){return $p -and [string]$p.ExecutablePath -eq $saved.File -and ([datetime]$p.CreationDate).ToString('o') -eq $saved.Created}
function DisableOtherZapret($plan){
 $path="$Data/other-zapret.json"
 if(Test-Path $path){throw 'Резервная копия прежних zapret уже существует. Сначала восстановите её.'}
 if(-not ($plan.Services.Count+$plan.Tasks.Count+$plan.Processes.Count)){throw 'Другие zapret не найдены'}
 SaveJson $plan $path
 $problems=New-Object Collections.Generic.List[string]
 foreach($t in $plan.Tasks){try{
  $now=Get-ScheduledTask -TaskName $t.Name -TaskPath $t.Path -ErrorAction Stop
  if((TaskSignature $now) -ne $t.Signature){throw 'Команда задачи изменилась'}
  Disable-ScheduledTask -TaskName $t.Name -TaskPath $t.Path|Out-Null
  if([string]$now.State -eq 'Running'){Stop-ScheduledTask -TaskName $t.Name -TaskPath $t.Path}
 }catch{$problems.Add($t.Name+': '+$_.Exception.Message)}}
 foreach($s in $plan.Services){try{
  $now=Get-CimInstance Win32_Service -Filter ("Name='"+$s.Name.Replace("'","''")+"'")
  if(-not $now -or (ServiceImage $now) -ne $s.Image){throw 'Служба изменилась после проверки'}
  Set-Service $s.Name -StartupType Disabled
  Stop-Service $s.Name -ErrorAction Stop
  (Get-Service $s.Name).WaitForStatus('Stopped',[timespan]::FromSeconds(15))
 }catch{$problems.Add($s.Name+': '+$_.Exception.Message)}}
 foreach($p in $plan.Processes){try{
  $now=Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)"
  if(SameProcess $now $p){Stop-Process -Id $p.Id -ErrorAction Stop}
 }catch{$problems.Add(('PID '+$p.Id+': '+$_.Exception.Message))}}
 if($problems.Count){throw ('Часть действий не выполнена. Копия для восстановления сохранена: '+($problems -join '; '))}
}
function RestoreOtherZapret {
 $path="$Data/other-zapret.json";$saved=ReadJson $path
 if(-not $saved){throw 'Нет сохранённых прежних zapret'}
 if(VpnOn){throw 'Отключите VPNUS перед восстановлением прежних zapret'}
 [void](OwnedService)
 $watch=Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
 if($watch){
  if(($watch.Actions.Arguments -join '') -notlike ('*"'+$PSScriptRoot+'\vpn-watch.ps1"*')){throw 'Задача этой сборки принадлежит другой копии'}
  Disable-ScheduledTask -TaskName $TaskName|Out-Null;Stop-ScheduledTask -TaskName $TaskName
 }
 $st=ReadJson "$Data/settings.json"
 if($st){$st.Desired=$false;$st.Auto=$false;SaveJson $st "$Data/settings.json"}
 StopOwn
 if(Get-Service $ServiceName -ErrorAction SilentlyContinue){Set-Service $ServiceName -StartupType Manual}
 $errors=New-Object Collections.Generic.List[string]
 foreach($s in $saved.Services){try{
  $now=Get-CimInstance Win32_Service -Filter ("Name='"+$s.Name.Replace("'","''")+"'")
  $image=if($now){ServiceImage $now}else{$null}
  if(-not $now -or $image -ne $s.Image -or -not(EnginePath $image)){throw 'Служба удалена или изменена; пропущена'}
  $mode=switch([int]$s.Start){2{'Automatic'}3{'Manual'}4{'Disabled'}default{throw 'Неизвестный режим запуска'}}
  Set-Service $s.Name -StartupType $mode
  Set-ItemProperty "HKLM:/SYSTEM/CurrentControlSet/Services/$($s.Name)" -Name DelayedAutoStart -Value ([int]$s.Delayed)
  if($s.Running){Start-Service $s.Name}
 }catch{$errors.Add($s.Name+': '+$_.Exception.Message)}}
 foreach($p in $saved.Processes){try{
  if($p.Restored){continue}
  $now=Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)"
  if(SameProcess $now $p){$p.Restored=$true;SaveJson $saved $path;continue}
  if(-not(EnginePath ('"'+$p.File+'"')) -or (Get-FileHash -LiteralPath $p.File -Algorithm SHA256).Hash -ne $p.Hash){throw 'Исполняемый файл изменился; автоматический запуск отменён'}
  $already=@(Get-CimInstance Win32_Process -Filter "Name='winws.exe' OR Name='winws2.exe'"|Where-Object {$_.ExecutablePath -eq $p.File -and $_.CommandLine -ceq $p.Command})
  if($already.Count){$p.Restored=$true;SaveJson $saved $path;continue}
  $m=[regex]::Match($p.Command,'^\s*(?:"[^"]+"|\S+)\s*(.*)$')
  $info=New-Object Diagnostics.ProcessStartInfo;$info.FileName=$p.File;$info.Arguments=$m.Groups[1].Value;$info.WorkingDirectory=Split-Path $p.File;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
  $proc=[Diagnostics.Process]::Start($info)
  try{if($proc.WaitForExit(600)){throw 'Отдельный winws завершился; запустите исходный BAT вручную'}}finally{$proc.Dispose()}
  $p.Restored=$true;SaveJson $saved $path
 }catch{$errors.Add(('PID '+$p.Id+': '+$_.Exception.Message))}}
 foreach($t in $saved.Tasks){try{
  $now=Get-ScheduledTask -TaskName $t.Name -TaskPath $t.Path -ErrorAction Stop
  if((TaskSignature $now) -ne $t.Signature){throw 'Команда задачи изменилась; пропущена'}
  if($t.Enabled -or $t.Running){Enable-ScheduledTask -TaskName $t.Name -TaskPath $t.Path|Out-Null}
  if($t.Running -and [string]$now.State -ne 'Running'){Start-ScheduledTask -TaskName $t.Name -TaskPath $t.Path}
  if(-not $t.Enabled){Disable-ScheduledTask -TaskName $t.Name -TaskPath $t.Path|Out-Null}
 }catch{$errors.Add($t.Name+': '+$_.Exception.Message)}}
 if($errors.Count){throw ('Восстановлено частично; резервная копия сохранена. '+($errors -join '; '))}
 Remove-Item -LiteralPath $path
}

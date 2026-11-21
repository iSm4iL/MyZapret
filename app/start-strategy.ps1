param([string]$Strategy)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $admin){Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Strategy "'+$Strategy+'"');return}
try{
    . "$PSScriptRoot/builder-core.ps1"
    BCheckDonor $Strategy
    $requestFile="$BuilderDir/direct-strategy.json";BSave @{Donor=$Strategy} $requestFile
    & "$PSScriptRoot/builder-action.ps1" -Action Base -RequestFile $requestFile
    & "$PSScriptRoot/builder-action.ps1" -Action Apply
    [Windows.Forms.MessageBox]::Show("Стратегия $Strategy применена. Автозапуск включается отдельно в панели.",'MyZapret')|Out-Null
}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'MyZapret — ошибка')|Out-Null}

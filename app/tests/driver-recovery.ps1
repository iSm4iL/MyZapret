$ErrorActionPreference='Stop'
. "$PSScriptRoot/../builder-core.ps1"
$repairImpl=${function:BRepairDriver}
$BuilderDir=Join-Path $PackageRoot ('data/tests/driver-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $BuilderDir|Out-Null
$log="$BuilderDir/test.json.log"
$command='wrapper.exe "'+$BuilderDir+'/test.json"'
function Get-ItemProperty {param($Path);[pscustomobject]@{ImagePath=$command}}
function Get-Service {param($Name);[pscustomobject]@{Status='Running'}}
function Start-Sleep {param($Seconds,$Milliseconds)}
function BStopService {param($Name)}
$script:starts=0;$script:repairs=0;$script:always=$false
function BRepairDriver {$script:repairs++}
function Start-Service {
    param($Name,$ErrorAction)
    $script:starts++
    if($script:always -or $script:starts -eq 1){[IO.File]::AppendAllText($log,"windivert: error opening filter: The object is referenced by other objects so cannot be deleted.`n");throw 'Injected conflict'}
}
BStartManagedService
if($script:starts -ne 2 -or $script:repairs -ne 0){throw 'Transient conflict not retried exactly once'}
$script:starts=0;$script:always=$true
$rejected=$false;try{BStartManagedService}catch{$rejected=$true}
if(-not $rejected -or $script:starts -ne 3 -or $script:repairs -ne 1){throw 'Persistent conflict not bounded/recovered'}
$script:starts=0;$script:always=$false
function Start-Service {param($Name,$ErrorAction);$script:starts++;throw 'Missing executable'}
$rejected=$false;try{BStartManagedService}catch{$rejected=$true}
if(-not $rejected -or $script:starts -ne 1){throw 'Old log caused unrelated failure to be retried'}
'PASS: transient filter conflict retried; persistent conflict bounded, own recovery once; old log cannot trigger recovery for unrelated failure.'

Set-Item Function:BRepairDriver $repairImpl
function BBootId {'test'}
function Get-Process {param($Name,$ErrorAction);return}
$script:driver=[pscustomobject]@{PathName=($PackageRoot+'\bin\WinDivert64.sys');State='Running'}
function Get-CimInstance {param($ClassName,$Filter);return $script:driver}
function sc.exe {param($verb,$name,$extra,$mode);if($verb -eq 'stop'){$script:driver=$null};$global:LASTEXITCODE=0}
BRepairDriver|Out-Null
if((BRead "$BuilderDir/driver-health.json").NeedsRestart){throw 'Disappeared driver falsely requires reboot'}
$script:driver=[pscustomobject]@{PathName='C:\OtherApp\WinDivert64.sys';State='Running'}
$rejected=$false;try{BRepairDriver|Out-Null}catch{$rejected=$true}
if(-not $rejected){throw 'Foreign driver was modified'}
'PASS: completed driver removal accepted; foreign installation refused.'

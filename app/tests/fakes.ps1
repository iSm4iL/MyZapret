# Test-only replacement of service, registry, process and HTTP operations.
if(-not $global:BFServices){
    $global:BFServices=@{zapret=[pscustomobject]@{Name='zapret';Status='Running';Start=2;ImagePath='old-engine-command'}}
    $global:BFTask=[pscustomobject]@{TaskName='zapret-auto-mode';TaskPath='\';State='Running'}
}
function Get-Service {param($Name,$ErrorAction);if($global:BFServices.ContainsKey($Name)){
    $s=$global:BFServices[$Name]
    if(-not $s.PSObject.Methods['WaitForStatus']){$s|Add-Member ScriptMethod WaitForStatus {param($state,$timeout);if($this.Status -ne $state){throw 'Wrong fake service state'}}}
    return $s
}}
function Get-ItemProperty {param($Path,$ErrorAction);$name=Split-Path $Path -Leaf;if($global:BFServices.ContainsKey($name)){return $global:BFServices[$name]}}
function Set-ItemProperty {param($Path,$Name,$Value);$key=Split-Path $Path -Leaf;$global:BFServices[$key].$Name=$Value}
function Set-Service {param($Name,$StartupType);$global:BFServices[$Name].Start=switch($StartupType){'Automatic'{2}'Manual'{3}'Disabled'{4}default{throw 'Unexpected fake startup type'}}}
function Stop-Service {param($Name,[switch]$Force);$global:BFServices[$Name].Status='Stopped'}
function Start-Service {param($Name);if($global:BFServices[$Name].Start -eq 4){throw 'Fake service disabled'};$global:BFServices[$Name].Status='Running'}
function Get-ScheduledTask {$global:BFTask}
function Disable-ScheduledTask {param($TaskName,$TaskPath);$global:BFTask.State='Disabled'}
function Stop-ScheduledTask {param($TaskName,$TaskPath);if($global:BFTask.State -ne 'Disabled'){$global:BFTask.State='Ready'}}
function Enable-ScheduledTask {param($TaskName,$TaskPath);$global:BFTask.State='Ready'}
function Start-ScheduledTask {param($TaskName,$TaskPath);$global:BFTask.State='Running'}
function Get-Process {param($Name,$ErrorAction);return}
function Vpn-Connected {return $false}
function BValidate {param($image);if($global:BFReject){throw 'Injected validation failure'};if($image -notmatch 'winws2.exe'){throw 'Fake validate: missing engine'};if(@($global:BFServices.Values|Where-Object {$_.Status -eq 'Running'}).Count){throw 'Duplicate filter: validation ran before service shutdown'}}
function BRunImage {param($image); $image=ConvertTo-ZapretServiceCommand $image "$BuilderDir/service-configs";
    if(-not $global:BFServices.ContainsKey('myzapret2')){$global:BFServices['myzapret2']=[pscustomobject]@{Name='myzapret2';Status='Stopped';Start=3;ImagePath=$image}}
    $global:BFServices['myzapret2'].ImagePath=$image;$global:BFServices['myzapret2'].Status='Running'
}
function sc.exe {param($verb,$name);if($verb -ne 'delete' -or $name -ne 'myzapret2'){throw 'Unexpected fake delete'};$global:BFServices.Remove($name);$global:LASTEXITCODE=0}
function curl.exe {
    $global:LASTEXITCODE=0
    if($global:BFCancel){[IO.File]::WriteAllText("$BuilderDir/cancel.flag",'cancel')}
    '200 0.05'
}

function BVideoProbe {param($directory);return [pscustomobject]@{Checked=$true;Pass=(-not $global:BFVideoFail);Details='Mock video bytes received'}}

function BResolveVideo {param($watch,$directory);return [pscustomobject]@{Url='https://localhost/videoplayback';UserAgent='Mock'}}
function BMediaTransfer {
    param($stream,$directory)
    if($stream.PinnedIP -ne '127.0.0.1'){throw 'Comparison did not pin the same IP'}
    $svc=$global:BFServices['myzapret2']
    return [pscustomobject]@{Pass=($svc.Status -eq 'Running' -and $svc.ImagePath -eq 'old-engine-command');Details='Mock same-endpoint comparison'}
}
function Set-ZapretServiceCommand {param($Name,$Image);$global:BFServices[$Name].ImagePath=$Image}

function BStartManagedService {Start-Service $BuilderService}

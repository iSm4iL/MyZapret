$ErrorActionPreference='Stop'
. "$PSScriptRoot/../builder-core.ps1"
$BuilderDir=Join-Path $PackageRoot ('data/vpn-tests/'+[guid]::NewGuid().ToString('N'))
$BuilderActive=Join-Path $BuilderDir 'active.json';$VpnLog=Join-Path $BuilderDir 'vpn.log'
New-Item -ItemType Directory -Force $BuilderDir|Out-Null
$global:TestBoot='100';$global:TestStarts=0;$global:TestStops=0
$global:TestService=[pscustomobject]@{Status='Running';Start=3;ImagePath='saved-command'}
$global:TestService|Add-Member ScriptMethod WaitForStatus {param($s,$t);if($this.Status -ne $s){throw 'Wrong service state'}}
function BBootId {$global:TestBoot}
function Get-Service {
    param($Name,$ErrorAction)
    if($Name -eq 'VpnusService'){return $script:TestVpnService}
    return $global:TestService
}
function Get-ItemProperty {param($Path);return $global:TestService}
function BStopService {param($Name);$global:TestStops++;$global:TestService.Status='Stopped'}
function Start-Service {param($Name);$global:TestStarts++;$global:TestService.Status='Running'}
function BStartManagedService {Start-Service $BuilderService}
function Get-Process {param($Name,$ErrorAction);return}
BSave @{ServiceImage='saved-command'} $BuilderActive
BSave @{Enabled=$true;DesiredRunning=$true;BootId='100'} "$BuilderDir/vpn-follow.json"
'[tunnel] connected'|Set-Content $VpnLog
BFollowStep|Out-Null;BFollowStep|Out-Null
if($global:TestService.Status -ne 'Stopped' -or $global:TestStops -ne 1){throw 'VPN ON failed or repeated stop'}
$script:TestVpnService=[pscustomobject]@{Status='Stopped'}
if((BVpnState) -ne 'Off'){throw 'Stopped VPN service treated stale connected log as active'}
$script:TestVpnService=[pscustomobject]@{Status='Running'}
if((BVpnState) -ne 'On'){throw 'Running VPN service ignored connected log'}
'[tunnel] disconnected'|Set-Content $VpnLog
BFollowStep|Out-Null
if($global:TestService.Status -ne 'Running' -or $global:TestStarts -ne 1){throw 'VPN OFF did not resume'}
BFollowWant $false;BStopService $BuilderService;BFollowStep|Out-Null
if($global:TestService.Status -ne 'Stopped'){throw 'Manual stop ignored'}
BFollowWant $true;$global:TestService.ImagePath='different-command';BFollowStep|Out-Null
if($global:TestService.Status -ne 'Stopped'){throw 'Unconfirmed command started'}
$global:TestService.ImagePath='saved-command';$global:TestBoot='101';BFollowStep|Out-Null
if($global:TestService.Status -ne 'Stopped'){throw 'Manual-start service resumed after reboot'}
$global:TestService.Start=2;$global:TestBoot='102';BFollowStep|Out-Null
if($global:TestService.Status -ne 'Running'){throw 'Automatic service not resumed after reboot'}
'[tunnel] connect: bringing up tunnel'|Set-Content $VpnLog;BFollowStep|Out-Null
if($global:TestService.Status -ne 'Stopped'){throw 'Connecting VPN did not pause service'}
''|Set-Content $VpnLog;BFollowStep|Out-Null
if($global:TestService.Status -ne 'Stopped'){throw 'Unknown VPN state caused restart'}
$guard=BControlLock
try{if(BControlLock 50){throw 'Service-control lock was not exclusive'}}finally{$guard.Dispose()}
$guard=BControlLock
if(-not $guard){throw 'Service-control lock leaked'};$guard.Dispose()
'PASS: VPN ON/OFF, manual stop, boot/autostart, command integrity, connecting and unknown state. Services mocked.'

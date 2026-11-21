$Root=$PackageRoot;$Data=$BuilderDir;$ServiceName=$BuilderService;$TaskName=$FollowTask;$DnsLabel='MyZapret Full Spotify images'
function ReadJson($p){BRead $p}
function SaveJson($v,$p){BSave $v $p}
function VpnOn {return Vpn-Connected}
function OwnedService {Get-CimInstance Win32_Service -Filter "Name='$BuilderService'" -ErrorAction SilentlyContinue}
function StopOwn {BFollowWant $false;BStopService $BuilderService}
function DnsApply([int]$index){
 if(Test-Path "$Data/dns.json"){throw 'DNS этой сборки уже настроен. Для выбора другой сети сначала восстановите DNS.'}
 $adapter=Get-NetAdapter -InterfaceIndex $index -ErrorAction Stop
 $gateway=@(Get-NetRoute -InterfaceIndex $index -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue|Where-Object {$_.NextHop -ne '0.0.0.0'}|Sort-Object RouteMetric|Select-Object -First 1)
 if(-not $gateway.Count){throw 'У выбранного адаптера нет IPv4-шлюза'}
 $domains=@('i.scdn.co','image-cdn-ak.spotifycdn.com','image-cdn-fa.spotifycdn.com')
 foreach($rule in @(Get-DnsClientNrptRule)){foreach($n in $domains){if($rule.Namespace -contains $n){throw ('Для '+$n+' уже есть DNS-правило. Оно оставлено без изменений.')}}}
 $guid=[guid]$adapter.InterfaceGuid
 $registry=Get-ItemProperty ('HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\'+$guid.ToString('B'))
 $saved=@{Guid=[string]$guid;Adapter=$adapter.Name;NameServer=[string]$registry.NameServer;Gateway=$gateway[0].NextHop;Rule=$null}
 SaveJson $saved "$Data/dns.json"
 try{
  Set-DnsClientServerAddress -InterfaceIndex $index -ServerAddresses @('1.1.1.1','1.0.0.1')
  $rule=Add-DnsClientNrptRule -Namespace $domains -NameServers $gateway[0].NextHop -DisplayName $DnsLabel -PassThru
  $saved.Rule=$rule.Name;SaveJson $saved "$Data/dns.json"
  Clear-DnsClientCache
 }catch{DnsRestore;throw}
}
function DnsRestore {
 $saved=ReadJson "$Data/dns.json"
 if(-not $saved){return}
 $adapter=@(Get-NetAdapter -IncludeHidden|Where-Object {([guid]$_.InterfaceGuid) -eq ([guid]$saved.Guid)})
 if($adapter.Count -ne 1){throw 'Исходный сетевой адаптер не найден; резервная копия DNS сохранена'}
 if($saved.Rule){
  $rule=Get-DnsClientNrptRule -Name $saved.Rule -ErrorAction SilentlyContinue
  if($rule){if($rule.DisplayName -ne $DnsLabel){throw 'DNS-правило изменено другим приложением'};Remove-DnsClientNrptRule -Name $saved.Rule -Force}
 }
 if([string]::IsNullOrWhiteSpace($saved.NameServer)){Set-DnsClientServerAddress -InterfaceIndex $adapter[0].ifIndex -ResetServerAddresses}
 else{Set-DnsClientServerAddress -InterfaceIndex $adapter[0].ifIndex -ServerAddresses @($saved.NameServer -split '[,;\s]+'|Where-Object {$_})}
 Clear-DnsClientCache
 Remove-Item -LiteralPath "$Data/dns.json"
}

. "$PSScriptRoot/other-zapret.ps1"
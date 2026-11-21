$ErrorActionPreference='Stop'
$dir=Join-Path "$PackageRoot/reports" ('Compare-YouTube-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force $dir|Out-Null
$old=BRead $BuilderOriginal;if(-not $old){$old=BSnapshot};$active=BRead $BuilderActive
$legacy=@($old.Services|Where-Object Name -eq 'zapret'|Select-Object -First 1)
if(-not $legacy.Count -and -not $active){throw 'Нет сохранённого состава и старой службы для сравнения.'}
function BOldStock([string]$folder){
    # Keep the old parser and its path variables inside this function scope.
    . "$PackageRoot/legacy/zapret_tool/zapret_core.ps1"
    $Root=$folder;$Lists=Join-Path $folder 'lists'
    return Build-ImagePath 'general (ALT11)' $false
}
function BCompareTcp([string]$ip){
    $client=New-Object Net.Sockets.TcpClient
    try{$task=$client.ConnectAsync($ip,443);if(-not $task.Wait(4000)){return $false};return $client.Connected}catch{return $false}finally{$client.Dispose()}
}
function BCompareTls([string]$ip,[string]$hostName){
    try{
        $raw=& node.exe "$BuilderLab/tls-probe.cjs" $ip $hostName 2>> "$dir/tls-probe-errors.txt"
        if($LASTEXITCODE -ne 0){throw "TLS probe exit=$LASTEXITCODE"}
        return ($raw -join '')|ConvertFrom-Json
    }catch{return [pscustomobject]@{actual=@{tcp=$false;tls=$false;error=$_.Exception.Message};control=@{tls=$false}}}
}
try{$vpnAddresses=@(Get-NetIPAddress -InterfaceAlias VPNUS -AddressFamily IPv4 -ErrorAction Stop|Select-Object -ExpandProperty IPAddress)}catch{$vpnAddresses=@()}
$cases=@([pscustomobject]@{Name='Без zapret';Image=$null})
if($active.ServiceImage){$cases+=[pscustomobject]@{Name='MyZapret — применённый';Image=$active.ServiceImage}}
if($legacy.Count){$cases+=[pscustomobject]@{Name='Старый zapret — сохранённый';Image=$legacy[0].Image}}
foreach($folder in @("$PackageRoot/legacy","$PackageRoot/legacy/DNS GANWO")){
    if(Test-Path "$folder/general (ALT11).bat"){$cases+=[pscustomobject]@{Name=('ALT11: '+(Split-Path $folder -Leaf));Image=(BOldStock $folder)}}
}
$stream=$null;$setupErrors=@()
foreach($image in @($active.ServiceImage,$legacy[0].Image)){
    if(-not $image){continue}
    if(Vpn-Connected){throw 'VPN connected during test; restoring original state.'}
    try{BRunImage $image;$stream=BResolveVideo (BWatchUrl $(if($request.WatchUrl){[string]$request.WatchUrl}else{[string](BVideoSettings).WatchUrl})) $dir;break}catch{if($_.Exception.Message -like 'Cancelled*' -or (Vpn-Connected)){throw};$setupErrors+=$_.Exception.Message}
}
if(-not $stream){throw ('Не удалось получить поток ни через новый, ни через старый состав: '+($setupErrors -join '; '))}
$ip=@([Net.Dns]::GetHostAddresses(([uri]$stream.Url).Host)|Where-Object AddressFamily -eq InterNetwork|Select-Object -First 1)[0]
if(-not $ip){throw 'У видеосервера нет IPv4-адреса.'}
$stream|Add-Member -NotePropertyName PinnedIP -NotePropertyValue $ip.IPAddressToString -Force
$rows=@();$index=0;$transportRows=@()
if($request.TransportMatrix){. "$BuilderLab/repair-lib.ps1"}
foreach($case in $cases){
    if(Test-Path "$BuilderDir/cancel.flag"){throw 'Cancelled; original state will be restored.'}
    if(Vpn-Connected){throw 'VPN connected during test; restoring original state.'}
    $index++
    BSave @{Donor=$case.Name;Index=$index;Total=$cases.Count;Stage='Сравнение одного видеопотока и IP'} "$BuilderDir/progress.json"
    BStopService $BuilderService
    $startupError=$null
    if($case.Image){try{BRunImage $case.Image}catch{$startupError=$_.Exception.Message}}
    $tcp=$false;$media=$null;$tls=$null
    if(-not $startupError){
        $tcp=BCompareTcp $stream.PinnedIP
        if($request.TransportMatrix){
            $caseProbes=@()
            foreach($mode in @('TLS12','TLS13','H3')){
                BRCheck
                $probe=BRRequest $stream $mode $dir
                BRCheck
                $probe|Add-Member -NotePropertyName Case -NotePropertyValue $case.Name -Force
                $caseProbes+=$probe;$transportRows+=$probe
                $transportRows|Export-Csv "$dir/transport-results.csv" -NoTypeInformation -Encoding UTF8
            }
            $media=[pscustomobject]@{Pass=(@($caseProbes|Where-Object Pass).Count -gt 0);Details='TLS1.2 / TLS1.3 / HTTP3: see transport-results.csv'}
        }else{$tls=BCompareTls $stream.PinnedIP ([uri]$stream.Url).Host;$media=BMediaTransfer $stream $dir}
        if(Vpn-Connected){throw 'VPN connected during transfer; this result is invalid. Previous state will be restored.'}
    }
    $rows+=[pscustomobject]@{Case=$case.Name;Host=([uri]$stream.Url).Host;IP=$stream.PinnedIP;TCP443=$tcp;TLSVideo=[bool]$tls.actual.tls;TLSControl=[bool]$tls.control.tls;LocalAddress=$tls.actual.local;UsesVpnAddress=($tls.actual.local -in $vpnAddresses);TLSError=$tls.actual.error;VideoPass=[bool]$media.Pass;Details=$(if($startupError){$startupError}else{$media.Details})}
    $rows|Export-Csv "$dir/results.csv" -NoTypeInformation -Encoding UTF8
    BSave @{Rows=$rows;Complete=$false;Report=$dir;VPN='Off'} "$BuilderDir/compare-results.json"
    "$($case.Name): TCP=$tcp, TLS видео=$([bool]$tls.actual.tls), TLS контроль=$([bool]$tls.control.tls), видео=$([bool]$media.Pass)"
}
BSave @{Rows=$rows;Complete=$true;Report=$dir;VPN='Off'} "$BuilderDir/compare-results.json"
$rows|ConvertTo-Html -Head '<meta charset="utf-8"><style>body{font:15px Segoe UI;margin:20px}td,th{border:1px solid #ccd;padding:8px}table{border-collapse:collapse}</style>' -PreContent '<h1>Один поток и IP: без zapret / новый / старый</h1><p>Сравнение временное. Настройки и службы восстанавливаются после теста.</p>'|Set-Content "$dir/table.html" -Encoding UTF8
"Сравнение завершено. Прошло видео: $(@($rows|Where-Object VideoPass).Count) из $($rows.Count). Отчёт: $dir"

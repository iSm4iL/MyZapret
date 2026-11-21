. "$BuilderLab/repair-lib.ps1"
. "$BuilderLab/focused-lib.ps1"
$script:BRDeadline=[datetime]::UtcNow.AddMinutes(15)
$dir=Join-Path "$PackageRoot/reports" ('Focused-YouTube-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force $dir|Out-Null
$sourceHash=BHash (BBuild $model);$active=BRead $BuilderActive
if(-not $active){throw 'Сначала примените состав для загрузки страницы YouTube.'}
$rows=New-Object Collections.Generic.List[object]
$capture=$null;$proxyMode=$null;$needsExclusion=$false;$confirmed=$false;$packetMethod=$null;$packetIPs=@();$checks=@()
function FocusProgress($name){BRCheck;BSave @{Donor='Новые TLS-методы';Index=$rows.Count;Total=24;Stage=$name} "$BuilderDir/progress.json"}
function FocusRecord($name,$result){$rows.Add([pscustomobject]@{Case=$name;Pass=[bool]$result.Pass;Mode=$result.Mode;HTTP=$result.HTTP;Curl=$result.Curl;Bytes=$result.Bytes;Host=$result.Host;Error=$result.Error});BSave @{Complete=$false;Rows=$rows.ToArray();Report=$dir;Confirmed=$false;SourceModelHash=$sourceHash} "$BuilderDir/repair-results.json"}
$watchCandidates=@((BWatchUrl ([string](BVideoSettings).WatchUrl)),'https://www.youtube.com/watch?v=YE7VzlLtp-4')|Select-Object -Unique
$bootstrapFailures=@()
$knownStreams=@()
$watches=$watchCandidates
foreach($bootstrap in @(@{Name='Активный состав';Image=$active.ServiceImage},@{Name='Черновик';Image=(BBuild $model)})){
    FocusProgress ("Получаем свежий поток: "+$bootstrap.Name)
    try{BRunImage $bootstrap.Image}catch{BRCheck;$bootstrapFailures+=($bootstrap.Name+': '+$_.Exception.Message);continue}
    foreach($watch in $watchCandidates){
        BRCheck
        try{
            $knownStreams+=BResolveVideo $watch $dir

        }catch{BRCheck;$bootstrapFailures+=($bootstrap.Name+' / '+$watch+': '+$_.Exception.Message)}
    }
    if($knownStreams.Count){break}
}
if($bootstrapFailures.Count){$bootstrapFailures|Set-Content "$dir/bootstrap-errors.txt" -Encoding UTF8}
if(-not $knownStreams.Count){throw "Страницы тестовых роликов недоступны на активном составе и черновике. Видеотест не начался. Отчёт: $dir"}
$stream=$knownStreams[0]
$targetIPs=@(foreach($s in $knownStreams){[Net.Dns]::GetHostAddresses(([uri]$s.Url).Host)|Where-Object AddressFamily -eq InterNetwork|ForEach-Object IPAddressToString})|Select-Object -Unique
$ip=@([Net.Dns]::GetHostAddresses(([uri]$stream.Url).Host)|Where-Object AddressFamily -eq InterNetwork|Select-Object -First 1)[0].IPAddressToString
BStopService $BuilderService
try{
    FocusProgress 'Захват TCP/TLS только проблемного IP, без zapret'
    $capture=BFCaptureStart $ip $dir
    BSave $capture "$dir/capture-status.json"
    FocusRecord 'baseline-System' (BRRequest $stream 'System' $dir)
    FocusRecord 'baseline-TLS13' (BRRequest $stream 'TLS13' $dir)
}finally{if($capture){BFCaptureStop $capture $dir}}
foreach($case in @(BFImages $ip)){
    FocusProgress $case.Name
    try{
        BStopService $BuilderService;BValidate $case.Image;BRunImage $case.Image;$tcpPass=$false
        foreach($mode in @('TLS13','TLS12')){BRCheck;$probe=BRRequest $stream $mode $dir;FocusRecord ($case.Name+'/'+$mode) $probe;if($probe.Pass){$tcpPass=$true}}
        if($tcpPass -and $knownStreams.Count -ge 2){
            $patched=$model|ConvertTo-Json -Depth 12|ConvertFrom-Json
            $patched|Add-Member -NotePropertyName PacketMethod -NotePropertyValue $case.Name -Force
            $patched|Add-Member -NotePropertyName PacketIPs -NotePropertyValue @($targetIPs) -Force
            BStopService $BuilderService;BValidate (BBuild $patched);BRunImage (BBuild $patched);$checks=@()
            foreach($watch in $watches){BRCheck;$fresh=BResolveVideo $watch $dir;$r=BRRequest $fresh 'System' $dir;FocusRecord ('confirm-packet/'+$case.Name) $r;$checks+=[bool]$r.Pass}
            if($checks.Count -ge 2 -and $false -notin $checks -and (BRPage $dir)){$confirmed=$true;$packetMethod=$case.Name;$packetIPs=@($targetIPs);break}
        }
    }catch{BRCheck;FocusRecord $case.Name ([pscustomobject]@{Mode='engine';Error=$_.Exception.Message})}
}
BStopService $BuilderService
foreach($mode in $(if($confirmed){@()}else{@('sni','record1','record5','tcp')})){
    FocusProgress ('Локальный CONNECT: '+$mode)
    $proxy=$null
    try{
        $proxy=BFProxyStart $mode $dir
        $trial=[pscustomobject]@{Url=$stream.Url;UserAgent=$stream.UserAgent;ProxyPort=$proxy.Status.Port}
        $initial=BRRequest $trial 'TLS13' $dir;FocusRecord ('proxy/'+$mode) $initial
        if(-not $initial.Pass){continue}
        # Keep the tested proxy separate from kernel TLS manipulation.
        $patched=$model|ConvertTo-Json -Depth 12|ConvertFrom-Json
        $patched|Add-Member -NotePropertyName LocalTlsProxy -NotePropertyValue $true -Force
        $image=BBuild $patched;BStopService $BuilderService;BValidate $image;BRunImage $image
        $checks=@()
        foreach($watch in @((BWatchUrl ([string](BVideoSettings).WatchUrl)),'https://www.youtube.com/watch?v=YE7VzlLtp-4')|Select-Object -Unique){
            BRCheck;$fresh=BResolveVideo $watch $dir
            $fresh|Add-Member -NotePropertyName ProxyPort -NotePropertyValue $proxy.Status.Port -Force
            $r=BRRequest $fresh 'System' $dir;FocusRecord ('confirm-proxy/'+$mode) $r;$checks+=[bool]$r.Pass
        }
        if($checks.Count -ge 2 -and $false -notin $checks -and (BRPage $dir)){$proxyMode=$mode;$needsExclusion=$true;$confirmed=$true;break}
    }catch{BRCheck;FocusRecord ('proxy/'+$mode) ([pscustomobject]@{Mode='proxy';Error=$_.Exception.Message})}
    finally{if($proxy){if(-not $proxy.Process.HasExited){$proxy.Process.Kill()};$proxy.Process.Dispose()};BStopService $BuilderService}
}
$result=@{Complete=$true;PlanVersion='focused-v1';Rows=$rows.ToArray();Report=$dir;SourceModelHash=$sourceHash;Confirmed=$confirmed;ConfirmationType=$(if($packetMethod){'PacketMethod'}else{'LocalProxy'});PacketMethod=$packetMethod;PacketIPs=$packetIPs;ProxyMode=$proxyMode;NeedsExclusion=$needsExclusion;Recommended=$null;Capture=$capture;Checks=$checks;VPN='Off'}
BSave $result "$BuilderDir/repair-results.json";BSave $result "$dir/result.json"
$rows.ToArray()|Export-Csv "$dir/results.csv" -Encoding UTF8 -NoTypeInformation
$rows.ToArray()|ConvertTo-Html -Head '<meta charset="utf-8"><style>body{font:15px Segoe UI}td,th{border:1px solid #ccd;padding:6px}</style>' -PreContent '<h1>Новые способы передачи TLS и захват пакетов</h1>'|Set-Content "$dir/table.html" -Encoding UTF8
"Точечная проверка завершена. Подтверждён локальный TLS-прокси: $confirmed, режим=$proxyMode. Отчёт: $dir"

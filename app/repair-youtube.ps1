. "$BuilderLab/repair-lib.ps1"
$script:BRDeadline=[datetime]::UtcNow.AddMinutes(45)
$dir=Join-Path "$PackageRoot/reports" ('Repair-YouTube-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force $dir|Out-Null
$sourceHash=BHash (BBuild $model)
$cases=@([pscustomobject]@{Name='Без zapret';Engine='none';Recipe=$null;Image=$null})
$active=BRead $BuilderActive
if($active){$cases+=[pscustomobject]@{Name='Применённый MyZapret';Engine='current';Recipe=$null;Image=$active.ServiceImage}}
foreach($id in Get-Configs){$candidate=BWithDonor $model 'youtube' $id;$cases+=[pscustomobject]@{Name=$id;Engine='winws2';Recipe=$id;Image=(BBuild $candidate)}}
$cases+=@(BROldCases)
$seen=@{};$cases=@($cases|Where-Object {$key=BHash ([string]$_.Image);if($seen.ContainsKey($key)){$false}else{$seen[$key]=$true;$true}})
$native=BRead "$BuilderDir/repair-native-validation.json"
$invalid=@{};foreach($entry in @($native.Rows|Where-Object {$_ -and $_.ImageHash -and -not $_.Valid})){$invalid[$entry.ImageHash]=$entry.Error}
$cases|Select-Object Name,Engine,Recipe|Export-Csv "$dir/plan.csv" -Encoding UTF8 -NoTypeInformation
$rows=New-Object Collections.Generic.List[object]
$recommended=$null;$confirmed=$false;$validation=@();$sampleErrors=@()
function BRProgress($name,$stage,[int]$index){BRCheck;BSave @{Donor=$name;Index=$index;Total=$cases.Count;Stage=$stage} "$BuilderDir/progress.json"}
function BRRecord($case,$scope,$result){
    $row=[pscustomobject]@{Case=$case.Name;Engine=$case.Engine;Recipe=$case.Recipe;Scope=$scope;Mode=$result.Mode;Pass=[bool]$result.Pass;Host=$result.Host;IP=$result.IP;HTTP=$result.HTTP;Curl=$result.Curl;Bytes=$result.Bytes;HTTPVersion=$result.HTTPVersion;DNS=$result.DNS;TCP=$result.TCP;TLS=$result.TLS;Error=$result.Error}
    $rows.Add($row)
    $row|ConvertTo-Json -Compress|Add-Content "$dir/results.jsonl" -Encoding UTF8
    BSave @{Complete=$false;Rows=@($rows.ToArray());Report=$dir;SourceModelHash=$sourceHash;Recommended=$null;Confirmed=$false} "$BuilderDir/repair-results.json"
}
$watches=@((BWatchUrl ([string](BVideoSettings).WatchUrl)),'https://www.youtube.com/watch?v=YE7VzlLtp-4')|Select-Object -Unique
$samples=@()
foreach($watch in $watches){
    $stream=$null
    foreach($bootstrap in @($cases|Where-Object Image|Select-Object -First 3)){
        BRProgress $bootstrap.Name 'Получение свежих адресов тестового видео' 0
        try{BRunImage $bootstrap.Image;$stream=BResolveVideo $watch $dir;break}catch{BRCheck;$sampleErrors+=$_.Exception.Message}
    }
    if($stream){$samples+=@{Watch=$watch;Stream=$stream}}
}
if(-not $samples.Count){throw ('Не удалось получить адреса видео: '+($sampleErrors -join '; '))}
$primary=$samples[0].Stream
$index=0
foreach($case in $cases){
    $index++;BRProgress $case.Name 'Запуск кандидата' $index
    BStopService $BuilderService
    if($case.Image -and $invalid.ContainsKey((BHash $case.Image))){BRRecord $case 'native validation' ([pscustomobject]@{Mode='skipped';Error=$invalid[(BHash $case.Image)]});continue}
    try{if($case.Image){BRunImage $case.Image}}catch{BRRecord $case 'startup' ([pscustomobject]@{Mode='startup';Error=$_.Exception.Message});continue}
    if($index -le 2){
        foreach($mode in @('System','GoogleDoH','CloudflareDoH','IPv6')){
            BRProgress $case.Name ("Сеть / $mode") $index
            if($mode -eq 'IPv6'){
                try{$v6=@([Net.Dns]::GetHostAddresses(([uri]$primary.Url).Host)|Where-Object AddressFamily -eq InterNetworkV6)}catch{$v6=@()}
                if(-not $v6.Count){BRRecord $case 'network' ([pscustomobject]@{Mode=$mode;Error='У видеосервера нет AAAA; IPv6 не проверялся'});continue}
            }
            BRRecord $case 'network' (BRRequest $primary $mode $dir)
        }
        foreach($alternative in @(BRStreams $primary|Where-Object Name -ne 'original')){
            foreach($mode in @('TLS13','H3')){BRProgress $case.Name ($alternative.Name+" / $mode") $index;BRRecord $case $alternative.Name (BRRequest $alternative.Stream $mode $dir)}
        }
    }
    $tcpPass=$false
    foreach($mode in @('TLS13','TLS12','H3')){
        BRProgress $case.Name ("Исходный CDN / $mode") $index
        $result=BRRequest $primary $mode $dir;BRRecord $case 'original CDN' $result
        if($mode -eq 'TLS13' -and $result.Pass){$tcpPass=$true}
    }
    if($case.Engine -eq 'winws2' -and $tcpPass -and $samples.Count -ge 2){
        $validation=@();BRProgress $case.Name 'Подтверждение на двух свежих видео обычным клиентом' $index
        foreach($sample in $samples){
            BRCheck
            try{$fresh=BResolveVideo $sample.Watch $dir;$probe=BRRequest $fresh 'System' $dir;BRRecord $case 'fresh confirmation' $probe;$validation+=@{Video=$sample.Watch;Pass=[bool]$probe.Pass}}catch{BRCheck;$validation+=@{Video=$sample.Watch;Pass=$false;Error=$_.Exception.Message}}
        }
        $pagePass=BRPage $dir
        if($pagePass -and @($validation|Where-Object {-not $_.Pass}).Count -eq 0){$recommended=$case.Recipe;$confirmed=$true;break}
    }
}
$result=@{Complete=$true;Rows=@($rows.ToArray());Report=$dir;SourceModelHash=$sourceHash;Recommended=$recommended;Confirmed=$confirmed;Validation=$validation;SampleErrors=$sampleErrors;PlannedCases=$cases.Count;CheckedCases=$index;VPN='Off';Note='Only real video bytes count as pass. QUIC/alternate-CDN success does not by itself confirm normal browser playback. No DNS/hosts/browser changes.'}
BSave $result "$BuilderDir/repair-results.json";BSave $result "$dir/result.json"
$rows.ToArray()|Export-Csv "$dir/results.csv" -Encoding UTF8 -NoTypeInformation
$rows.ToArray()|ConvertTo-Html -Head '<meta charset="utf-8"><style>body{font:15px Segoe UI;margin:20px}td,th{border:1px solid #ccd;padding:6px}table{border-collapse:collapse}</style>' -PreContent '<h1>Полная проверка восстановления YouTube</h1><p>Успех — полученные видеоданные. Успех QUIC/другого CDN требует отдельного подтверждения браузера. При нахождении повторно подтверждённого winws2-кандидата перебор прекращается.</p>'|Set-Content "$dir/table.html" -Encoding UTF8
"Полная проверка завершена: $index из $($cases.Count) кандидатов. Подтверждённый рецепт: $recommended. Отчёт: $dir"

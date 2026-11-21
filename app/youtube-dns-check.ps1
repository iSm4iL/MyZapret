param([string]$OutputDir,[switch]$AllowVpn)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/builder-core.ps1"
$vpn=BVpnState
if($vpn -ne 'Off' -and -not $AllowVpn){throw 'Для проверки пути провайдера отключите VPN.'}
if(-not $OutputDir){$OutputDir=Join-Path "$PackageRoot/reports" ('YouTube-DNS-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))}
New-Item -ItemType Directory -Force $OutputDir|Out-Null
try{$dns=@(Get-DnsClientServerAddress -AddressFamily IPv4|Select-Object InterfaceAlias,ServerAddresses)}catch{$dns=@($_.Exception.Message)}
$targets=@(@{Host='www.youtube.com';Url='https://www.youtube.com/';Media=$false},@{Host='i.ytimg.com';Url='https://i.ytimg.com/vi/aqz-KE-bpKQ/hqdefault.jpg';Media=$false})
$extractorError=$null
try{$stream=BResolveVideo (BWatchUrl ([string](BVideoSettings).WatchUrl)) $OutputDir;$targets+=@{Host=([uri]$stream.Url).Host;Url=$stream.Url;Media=$true}}catch{$extractorError=$_.Exception.Message}
$rows=@()
foreach($target in $targets){
    if(Test-Path "$BuilderDir/cancel.flag"){throw 'Cancelled; original state will be restored.'}
    $system=@();$systemError=$null;$doh=@();$dohError=$null
    try{$system=@(Resolve-DnsName $target.Host -Type A -DnsOnly -ErrorAction Stop|Where-Object IPAddress|Select-Object -ExpandProperty IPAddress)}catch{$systemError=$_.Exception.Message}
    $prior=$ErrorActionPreference;$ErrorActionPreference='Continue'
    try{$answer=& curl.exe -4 -sS --noproxy '*' --connect-timeout 4 --max-time 8 -H 'accept: application/dns-json' ('https://dns.google/resolve?name='+$target.Host+'&type=A') 2>> "$OutputDir/doh-errors.txt";$exitCode=$LASTEXITCODE}finally{$ErrorActionPreference=$prior}
    try{if($exitCode -ne 0){throw "DoH curl=$exitCode"};$json=($answer -join '')|ConvertFrom-Json;$doh=@($json.Answer|Where-Object type -eq 1|Select-Object -ExpandProperty data)}catch{$dohError=$_.Exception.Message}
    $paths=@([pscustomobject]@{Name='Обычный DNS';IP=$null})
    foreach($ip in @($doh|Select-Object -First 2)){$paths+=[pscustomobject]@{Name='IP из Google DoH';IP=$ip}}
    foreach($path in $paths){
        $argsList=@('-4','-sS','--noproxy','*','--connect-timeout','5','--max-time','12','-o','NUL','-w','%{http_code}|%{remote_ip}|%{time_namelookup}|%{time_connect}|%{time_appconnect}|%{size_download}')
        if($path.IP){$argsList+=@('--resolve',($target.Host+':443:'+$path.IP))}
        if($target.Media){$argsList+=@('--range','0-262143','--max-filesize','1048576','--user-agent',$stream.UserAgent)}else{$argsList+='--head'}
        $prior=$ErrorActionPreference;$ErrorActionPreference='Continue'
        try{$output=& curl.exe @argsList ([string]$target.Url) 2>> "$OutputDir/transport-errors.txt";$code=$LASTEXITCODE}finally{$ErrorActionPreference=$prior}
        $p=("$output").Trim() -split '\|'
        $rows+=[pscustomobject]@{Host=$target.Host;Mode=$path.Name;PinnedIP=$path.IP;SystemAnswers=($system -join ',');DoHAnswers=($doh -join ',');HTTP=$p[0];Curl=$code;RemoteIP=$p[1];DNS=$p[2];TCP=$p[3];TLS=$p[4];Bytes=$p[5];SystemError=$systemError;DoHError=$dohError}
    }
}
$result=[ordered]@{Time=(Get-Date).ToString('s');VPN=$vpn;AdapterDNS=$dns;ExtractorError=$extractorError;Rows=$rows;Note='Read-only. Different CDN DNS answers are normal and do not by themselves prove DNS poisoning. --resolve is used only inside diagnostic curl; system/browser DNS unchanged.'}
$result|ConvertTo-Json -Depth 8|Set-Content "$OutputDir/result.json" -Encoding UTF8
$intro='<h1>YouTube / DNS</h1><p>VPN: '+[Net.WebUtility]::HtmlEncode($vpn)+'</p><p>Сравнение обычного соединения с адресами Google DoH. Настройки DNS не менялись. При включённом VPN это проверка маршрута VPN, а не провайдера.</p>'
$rows|ConvertTo-Html -Head '<meta charset="utf-8"><style>body{font:15px Segoe UI;margin:20px}td,th{border:1px solid #ccd;padding:6px}table{border-collapse:collapse}</style>' -PreContent $intro|Set-Content "$OutputDir/table.html" -Encoding UTF8
"DNS/YouTube report: $OutputDir"
$normal=@($rows|Where-Object Mode -eq 'Обычный DNS')
$failed=@($normal|Where-Object {$_.Curl -ne 0 -or $_.HTTP -notmatch '^[23]'})
"Диагностика завершена: обычное соединение прошло для $($normal.Count-$failed.Count) из $($normal.Count) адресов. Это отчёт, а не подтверждение работы YouTube."
foreach($row in $failed){"Не прошёл $($row.Host): HTTP=$($row.HTTP), curl=$($row.Curl), DNS=$($row.DNS)s, TCP=$($row.TCP)s, TLS=$($row.TLS)s. Подробности — result.json."}

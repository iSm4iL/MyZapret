function BRPresets {
    $extra=[ordered]@{}
    foreach($ttl in @(3,4,5,6,8,10,12)){$extra[('20-fake-ttl'+$ttl)]=@(('--lua-desync fake:blob=fake_default_tls:ip_ttl='+$ttl+':repeats=8'),'--lua-desync multisplit:pos=1,midsld')}
    $extra['21-fakedsplit-mid']=@('--lua-desync fakedsplit:pos=midsld:tcp_seq=-10000')
    $extra['22-disorder-host']=@('--lua-desync multidisorder:pos=host+1,midsld')
    $extra['23-hostfake-md5']=@('--lua-desync hostfakesplit:host=www.google.com:midhost=midsld:tcp_md5')
    foreach($id in $extra.Keys){
        $path="$PackageRoot/strategies/$id.json"
        if(-not(Test-Path $path)){BSave @{Title=$id;Origin='Targeted YouTube TLS candidates; unverified until live probe';Tls=$extra[$id];QuicRepeats=8} $path}
    }
}
function BRCheck {
    if($script:BRDeadline -and [datetime]::UtcNow -gt $script:BRDeadline){throw 'Достигнут лимит 45 минут; состояние служб будет восстановлено. Частичные результаты сохранены.'}
    if(Test-Path "$BuilderDir/cancel.flag"){throw 'Cancelled; original state will be restored.'}
    if(Vpn-Connected){throw 'VPN connected during test; restoring original state.'}
}
function BRStreams($stream){
    $items=@([pscustomobject]@{Name='original';Stream=$stream})
    $uri=[uri]$stream.Url
    $mn=[regex]::Match($uri.Query,'[?&]mn=([^&]+)')
    if($mn.Success -and $uri.Host -match '^(rr?\d+)---'){
        $prefix=$Matches[1]
        foreach($suffix in ([uri]::UnescapeDataString($mn.Groups[1].Value) -split ',')){
            if($suffix -notmatch '^sn-[a-z0-9-]+$'){continue}
            $builder=[UriBuilder]::new($uri);$builder.Host=$prefix+'---'+$suffix+'.googlevideo.com'
            if($builder.Host -eq $uri.Host){continue}
            $items+=[pscustomobject]@{Name='alternate CDN';Stream=[pscustomobject]@{Url=$builder.Uri.AbsoluteUri;UserAgent=$stream.UserAgent}}
        }
    }
    $redirect=[UriBuilder]::new($uri);$redirect.Host='redirector.googlevideo.com'
    $items+=[pscustomobject]@{Name='YouTube redirector';Stream=[pscustomobject]@{Url=$redirect.Uri.AbsoluteUri;UserAgent=$stream.UserAgent}}
    return @($items|Select-Object -First 4)
}
function BRRunCurl([string]$exe,$arguments,[string]$directory){
    $prior=$ErrorActionPreference;$ErrorActionPreference='Continue'
    try{$output=& $exe @arguments 2>> "$directory/transport-errors.txt";$code=$LASTEXITCODE}finally{$ErrorActionPreference=$prior}
    return [pscustomobject]@{Raw=("$output");Code=$code}
}
function BRRequest($stream,[string]$mode,[string]$directory){
    $dependency=BRead "$PackageRoot/docs/curl-h3-dependency.json"
    $bundled=Join-Path $PackageRoot 'bin\curl-h3\curl-8.23.0_6-win64-mingw\bin\curl.exe'
    $exe=if($mode -eq 'System'){'curl.exe'}elseif(Test-Path $bundled){$bundled}else{(Join-Path $PackageRoot 'bin/curl-h3/curl-8.23.0_6-win64-mingw/bin/curl.exe')}
    $argsList=@('-q','-sS','-L','--max-redirs','2','--proto','=https','--proto-redir','=https','--noproxy','*','--connect-timeout','4','--max-time','9','--max-filesize','1048576','--range','0-262143')
    if($mode -eq 'IPv6'){$argsList+='-6'}else{$argsList+='-4'}
    switch($mode){
        TLS12 {$argsList+=@('--tlsv1.2','--tls-max','1.2','--http1.1')}
        TLS13 {$argsList+=@('--tlsv1.3','--tls-max','1.3','--http2')}
        H3 {$argsList+='--http3-only'}
        GoogleDoH {$argsList+=@('--doh-url','https://dns.google/dns-query')}
        CloudflareDoH {$argsList+=@('--doh-url','https://cloudflare-dns.com/dns-query')}
    }
    if($stream.PinnedIP -and $mode -in @('TLS12','TLS13','H3')){$argsList+=@('--resolve',(([uri]$stream.Url).Host+':443:'+$stream.PinnedIP))}
    if($stream.ProxyPort){$argsList+=@('--proxy',('http://127.0.0.1:'+$stream.ProxyPort),'--noproxy=')}
    if($stream.UserAgent -and $stream.UserAgent -notmatch '[\r\n]'){$argsList+=@('--user-agent',[string]$stream.UserAgent)}
    $file=Join-Path $directory ('part-'+[guid]::NewGuid().ToString('N')+'.bin')
    $argsList+=@('-o',$file,'-w','%{http_code}|%{content_type}|%{remote_ip}|%{time_namelookup}|%{time_connect}|%{time_appconnect}|%{http_version}|%{url_effective}',[string]$stream.Url)
    $response=BRRunCurl $exe $argsList $directory;$code=$response.Code
    $p=($response.Raw).Trim() -split '\|';$bytes=if(Test-Path $file){(Get-Item $file).Length}else{0}
    $finalHost=$null;try{$finalHost=([uri]$p[7]).Host}catch{}
    $pass=$code -eq 0 -and $p[0] -in @('200','206') -and $bytes -ge 16384 -and $p[1] -match '^video/' -and $finalHost -match '(^|\.)googlevideo\.com$'
    if(Test-Path $file){Remove-Item -LiteralPath $file}
    return [pscustomobject]@{Pass=$pass;Mode=$mode;HTTP=$p[0];Curl=$code;Bytes=$bytes;Mime=$p[1];IP=$p[2];DNS=$p[3];TCP=$p[4];TLS=$p[5];HTTPVersion=$p[6];Host=$finalHost}
}
function BRPage([string]$directory){
    $prior=$ErrorActionPreference;$ErrorActionPreference='Continue'
    try{$code=& curl.exe -q -4 -sS -L --noproxy '*' --connect-timeout 4 --max-time 8 -o NUL -w '%{http_code}' 'https://www.youtube.com/' 2>> "$directory/page-errors.txt";$exitCode=$LASTEXITCODE}finally{$ErrorActionPreference=$prior}
    return $exitCode -eq 0 -and ("$code").Trim() -match '^[23]\d\d$'
}
function BROldCases {
    $saved=BRead $BuilderOriginal
    foreach($s in @($saved.Services|Where-Object Name -eq 'zapret')){[pscustomobject]@{Name='Saved legacy';Engine='winws';Recipe=$null;Image=$s.Image}}
    foreach($folder in @("$PackageRoot/legacy","$PackageRoot/legacy/DNS GANWO","$PackageRoot/legacy/DNS GANWO/196 батники")){
        if(-not(Test-Path $folder)){continue}
        $folder=(Get-Item -LiteralPath $folder).FullName
        foreach($file in @(Get-ChildItem $folder -Filter *.bat|Where-Object Name -notin @('service.bat','test.bat'))){
            try{
                $image=& {
                    param($folder,$name)
                    . "$PackageRoot/legacy/zapret_tool/zapret_core.ps1"
                    $Root=$folder;$Lists=Join-Path $folder 'lists'
                    $image=Build-ImagePath $name $false
                    if(-not(Test-Path "$folder/bin/winws.exe")){$assets=Split-Path $folder;$image=$image.Replace(($folder+'\bin\'),($assets+'\bin\')).Replace(($folder+'\lists\'),($assets+'\lists\'))}
                    return $image.Replace('%GameFilter%','12')
                } $folder $file.BaseName
                if($image){
                    $missing=[IO.Path]::GetFullPath("$PackageRoot/legacy/DNS GANWO/bin/tls_clienthello_www_onetrust_com.bin")
                    $ourFake=Join-Path $PackageRoot 'bin/fakes/tls_clienthello_www_onetrust_com.bin'
                    $adapted=$image.Contains($missing) -and (Test-Path $ourFake)
                    if($adapted){$image=$image.Replace($missing,$ourFake)}
                    [pscustomobject]@{Name=((Split-Path $folder -Leaf)+' / '+$file.BaseName+$(if($adapted){' [our TLS fake]'}else{''}));Engine='winws';Recipe=$null;Image=$image}
                }
            }catch{[IO.File]::AppendAllText("$BuilderDir/repair-skipped.txt",($file.Name+': '+$_.Exception.Message+"`r`n"))}
        }
    }
}

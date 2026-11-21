$script:BVideoCache=$null
$DefaultVideoUrl='https://www.youtube.com/watch?v=aqz-KE-bpKQ'
function BVideoSettings {return BRead "$BuilderDir/youtube-media.json"}
function BProbeHash {$v=BVideoSettings;return BHash ('auto-media-v1|'+[string]$v.Url+'|'+[string]$v.WatchUrl+'|'+$DefaultVideoUrl)}
function BWatchUrl([string]$url){
    if(-not $url){return $DefaultVideoUrl}
    $uri=$null
    if(-not [uri]::TryCreate($url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.Port -ne 443 -or $uri.UserInfo){throw 'Вставьте HTTPS-ссылку на ролик YouTube или оставьте поле пустым для тестового ролика.'}
    $id=$null
    if($uri.Host -eq 'youtu.be'){$id=$uri.AbsolutePath.Trim('/')}
    elseif($uri.Host -in @('youtube.com','www.youtube.com','m.youtube.com')){
        if($uri.AbsolutePath -eq '/watch'){$m=[regex]::Match($uri.Query,'[?&]v=([A-Za-z0-9_-]{11})(?:&|$)');if($m.Success){$id=$m.Groups[1].Value}}
        else{$m=[regex]::Match($uri.AbsolutePath,'^/(?:shorts|embed)/([A-Za-z0-9_-]{11})/?$');if($m.Success){$id=$m.Groups[1].Value}}
    }
    if($id -notmatch '^[A-Za-z0-9_-]{11}$'){throw 'Нужна ссылка на конкретный ролик YouTube (watch, youtu.be или shorts), а не на канал или плейлист.'}
    return 'https://www.youtube.com/watch?v='+$id
}
function BMediaUrl([string]$url){
    $uri=$null
    return [uri]::TryCreate($url,[UriKind]::Absolute,[ref]$uri) -and $uri.Scheme -eq 'https' -and $uri.Port -eq 443 -and -not $uri.UserInfo -and $uri.Host -match '(^|\.)googlevideo\.com$' -and $uri.AbsolutePath -eq '/videoplayback'
}
function BSetVideo([string]$url){
    if($url -and (BMediaUrl $url)){$settings=@{Url=$url;WatchUrl=$null}}
    else{$settings=@{Url=$null;WatchUrl=(BWatchUrl $url)}}
    $settings.Saved=(Get-Date).ToString('s');BSave $settings "$BuilderDir/youtube-media.json";$script:BVideoCache=$null
}
function BResolveVideo([string]$watch,[string]$directory){
    $exe=Join-Path $PackageRoot 'bin/yt-dlp.exe'
    if(-not(Test-Path $exe)){throw 'Не найден bin/yt-dlp.exe для автоматической проверки видео.'}
    $node=Get-Command node.exe -ErrorAction SilentlyContinue
    if(-not $node){throw 'Для определения потока нужен установленный Node.js.'}
    $info=New-Object Diagnostics.ProcessStartInfo;$info.FileName=$exe
    $info.Arguments='--ignore-config --no-plugin-dirs --no-remote-components --no-cache-dir --no-playlist --skip-download --dump-single-json --force-ipv4 --proxy "" --socket-timeout 5 --retries 0 --extractor-retries 0 --no-js-runtimes --js-runtimes "node:'+ $node.Source+'" -f "worst[protocol=https][vcodec!=none]/worstvideo[protocol=https]" "'+$watch+'"'
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.StandardOutputEncoding=[Text.Encoding]::UTF8;$info.StandardErrorEncoding=[Text.Encoding]::UTF8
    $process=New-Object Diagnostics.Process;$process.StartInfo=$info
    try{
        [void]$process.Start();$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync();$until=[datetime]::UtcNow.AddSeconds(45)
        while(-not $process.WaitForExit(200)){
            if($script:BRRequireNoVpn -and (Vpn-Connected)){$process.Kill();throw 'VPN connected during test; restoring original state.'}
            if(Test-Path "$BuilderDir/cancel.flag"){$process.Kill();throw 'Cancelled; original state will be restored.'}
            if([datetime]::UtcNow -gt $until){$process.Kill();throw 'Не удалось получить адрес потока за 45 секунд.'}
        }
        if($process.ExitCode -ne 0){
            $message=($stderr.Result -replace 'https?://\S+','[URL]');if($message.Length -gt 1200){$message=$message.Substring($message.Length-1200)}
            [IO.File]::AppendAllText("$directory/video-extractor-errors.txt",$message+"`r`n")
            throw ("Не удалось получить поток YouTube: "+$message.Trim())
        }
        $meta=$stdout.Result|ConvertFrom-Json
        if(-not(BMediaUrl ([string]$meta.url)) -or $meta.vcodec -eq 'none'){throw 'YouTube не предоставил прямой HTTPS-видеопоток.'}
        return [pscustomobject]@{Url=[string]$meta.url;UserAgent=[string]$meta.http_headers.'User-Agent';WatchUrl=$watch;Time=[datetime]::UtcNow}
    }finally{$process.Dispose()}
}
function BVideoProbe([string]$directory){
    $v=BVideoSettings;$stream=$null
    if($v.Url){
        $expiry=[regex]::Match($v.Url,'[?&]expire=(\d+)')
        if($expiry.Success -and [DateTimeOffset]::FromUnixTimeSeconds([long]$expiry.Groups[1].Value) -lt [DateTimeOffset]::UtcNow){return [pscustomobject]@{Checked=$false;Pass=$false;Details='Ручной адрес потока истёк. Очистите поле для автоматического теста.'}}
        $stream=[pscustomobject]@{Url=$v.Url;UserAgent='Mozilla/5.0'}
    }else{
        $watch=BWatchUrl ([string]$v.WatchUrl)
        try{
            if($script:BVideoCache -and $script:BVideoCache.WatchUrl -eq $watch -and $script:BVideoCache.Time -gt [datetime]::UtcNow.AddMinutes(-10)){$stream=$script:BVideoCache}
            else{$stream=BResolveVideo $watch $directory;$script:BVideoCache=$stream}
        }catch{
            if($_.Exception.Message -like 'Cancelled*'){throw}
            return [pscustomobject]@{Checked=$false;Pass=$false;Details=$_.Exception.Message}
        }
    }
    $local=BRead "$BuilderDir/local-tls-proxy.json";$proxy=$null
    try{
        if($local.Enabled -and $local.Confirmed -and (BRead $BuilderActive).Model.LocalTlsProxy){$proxy=BFProxyStart $local.Mode $directory;$stream|Add-Member -NotePropertyName ProxyPort -NotePropertyValue $proxy.Status.Port -Force}
        return BMediaTransfer $stream $directory
    }finally{if($proxy){if(-not $proxy.Process.HasExited){$proxy.Process.Kill()};$proxy.Process.Dispose()}}
}
function BMediaTransfer($stream,[string]$directory){
    $file=Join-Path $directory 'media-part.bin';$prior=$ErrorActionPreference;$ErrorActionPreference='Continue'
    try{
        $agent=if($stream.UserAgent -and $stream.UserAgent -notmatch '[\r\n]'){$stream.UserAgent}else{'Mozilla/5.0'}
        $resolve=@();if($stream.PinnedIP){$resolve=@('--resolve',(([uri]$stream.Url).Host+':443:'+$stream.PinnedIP))}
        if($stream.ProxyPort){$resolve+=@('--proxy',('http://127.0.0.1:'+$stream.ProxyPort),'--noproxy=')}
        $raw=& curl.exe -4 -sS --noproxy '*' --user-agent $agent --connect-timeout 8 --max-time 20 --max-filesize 1048576 --range 0-262143 @resolve -o $file -w '%{http_code}|%{size_download}|%{content_type}|%{remote_ip}|%{time_namelookup}|%{time_connect}|%{time_appconnect}' ([string]$stream.Url) 2>> "$directory/media-errors.txt"
        $code=$LASTEXITCODE
    }finally{$ErrorActionPreference=$prior}
    $parts=("$raw").Trim() -split '\|';$bytes=if(Test-Path $file){(Get-Item $file).Length}else{0};$mime=if($parts.Count -ge 3){$parts[2]}else{''}
    $pass=$code -eq 0 -and $parts[0] -in @('200','206') -and $bytes -ge 16384 -and $mime -match '^video/'
    if(Test-Path $file){Remove-Item -LiteralPath $file};if(-not $pass){$script:BVideoCache=$null}
    $hostName=([uri]$stream.Url).Host
    $trace=[ordered]@{Time=(Get-Date).ToString('s');Donor=(BRead "$BuilderDir/progress.json").Donor;Host=$hostName;HTTP=$parts[0];Curl=$code;Bytes=$bytes;Mime=$mime;RemoteIP=$parts[3];DNS=$parts[4];TCP=$parts[5];TLS=$parts[6]}
    [IO.File]::AppendAllText("$directory/video-network.jsonl",(($trace|ConvertTo-Json -Compress)+"`r`n"),[Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{Checked=$true;Pass=$pass;Details="Видеофрагмент: HTTP=$($parts[0]) curl=$code bytes=$bytes type=$mime; CDN=$hostName IP=$($parts[3]) DNS=$($parts[4])s TCP=$($parts[5])s TLS=$($parts[6])s. TCP/IPv4, не полный тест плеера."}
}

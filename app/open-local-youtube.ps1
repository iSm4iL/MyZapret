$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
try{
    . "$PSScriptRoot/builder-core.ps1"
    $config=BRead "$BuilderDir/local-tls-proxy.json"
    $mode=if($config.Mode){[string]$config.Mode}else{'sni'}
    if($mode -notin @('sni','record1','record5','tcp')){throw 'Неизвестный режим локального TLS'}
    $statusFile="$BuilderDir/browser-proxy-$mode.json";$status=BRead $statusFile
    $process=if($status.PID){Get-Process -Id ([int]$status.PID) -ErrorAction SilentlyContinue}else{$null}
    $valid=$process -and $process.ProcessName -eq 'node' -and $status.Started -and [math]::Abs(($process.StartTime.ToUniversalTime()-[datetime]::Parse($status.Started).ToUniversalTime()).TotalSeconds) -lt 5
    if(-not $valid){
        $node=(Get-Command node.exe -ErrorAction Stop).Source
        $process=Start-Process $node -ArgumentList ('"'+$BuilderLab+'\tls-record-proxy.cjs" '+$mode+' 0 "'+$statusFile+'" vpn-aware') -WindowStyle Hidden -PassThru
        $null=$process.Handle
        for($i=0;$i -lt 30;$i++){Start-Sleep -Milliseconds 100;$status=BRead $statusFile;if($status.PID -eq $process.Id){break}}
        if($status.PID -ne $process.Id){throw 'Не удалось запустить локальный прокси'}
    }
    $browsers=@("${env:ProgramFiles}\Google\Chrome\Application\chrome.exe","${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe","${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe","${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe")
    $browser=@($browsers|Where-Object {Test-Path -LiteralPath $_}|Select-Object -First 1)[0]
    if(-not $browser){throw 'Не найден Chrome или Edge'}
    $profile="$BuilderDir/youtube-browser-$mode"
    $arguments='--user-data-dir="'+$profile+'" --proxy-pac-url="http://127.0.0.1:'+$status.Port+'/youtube.pac" --no-first-run "https://www.youtube.com/"'
    Start-Process -FilePath $browser -ArgumentList $arguments
}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Локальный YouTube')|Out-Null}

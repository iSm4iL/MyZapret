param([int]$WaitMinutes=60,[switch]$TransportMatrix)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$OutputEncoding=[Text.Encoding]::UTF8
. "$PSScriptRoot/builder-core.ps1"
BInitialize
$dir=Join-Path "$PackageRoot/reports" ('YouTube-Control-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
[void][IO.Directory]::CreateDirectory($dir)
$stateFile="$BuilderDir/control-test.json"
$mutex=[Threading.Mutex]::new($false,'Local\MyZapretControlTest')
if(-not $mutex.WaitOne(0)){throw 'A YouTube control test is already waiting or running.'}
function ControlState($phase,$message){
    BSave @{State=$phase;Message=$message;PID=$PID;Report=$dir;Time=(Get-Date).ToString('s')} $stateFile
    [IO.File]::AppendAllText("$dir/run.log",((Get-Date -Format s)+' '+$message+"`r`n"),[Text.UTF8Encoding]::new($true))
}
try{
    if(Test-Path "$BuilderDir/control-cancel.flag"){Remove-Item "$BuilderDir/control-cancel.flag"}
    ControlState Waiting 'Waiting for VPN to disconnect. No network settings have been changed.'
    $deadline=[datetime]::UtcNow.AddMinutes($WaitMinutes)
    while((BVpnState) -ne 'Off'){
        if(Test-Path "$BuilderDir/control-cancel.flag"){throw 'Cancelled before testing.'}
        if([datetime]::UtcNow -gt $deadline){throw 'VPN did not disconnect before the waiting deadline.'}
        Start-Sleep -Seconds 2
    }
    Start-Sleep -Seconds 4
    $verifiedSource=BRead $BuilderActive;$sourceHash=if($verifiedSource){BHash $verifiedSource.ServiceImage}else{''}
    $rounds=@([pscustomobject]@{Name='Default video';WatchUrl=(BWatchUrl ([string](BVideoSettings).WatchUrl))},[pscustomobject]@{Name='Second video';WatchUrl='https://www.youtube.com/watch?v=jNQXAC9IVRw'})
    foreach($round in $rounds){
        if(Vpn-Connected){throw 'VPN reconnected; further tests cancelled.'}
        if(Test-Path "$BuilderDir/control-cancel.flag"){throw 'Cancelled between tests.'}
        ControlState Running ('Testing '+$round.Name+'. Existing engine settings are restored after each round.')
        $request=Join-Path $dir ('request-'+[guid]::NewGuid().ToString('N')+'.json')
        BSave @{WatchUrl=$round.WatchUrl;TransportMatrix=[bool]$TransportMatrix} $request
        $savedPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
        try{$output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot/builder-job.ps1" -Action CompareYouTube -RequestFile $request 2>&1
        $code=$LASTEXITCODE}finally{$ErrorActionPreference=$savedPreference}
        [IO.File]::AppendAllText("$dir/run.log",(($output -join "`r`n")+"`r`n"),[Text.UTF8Encoding]::new($true))
        if($code -ne 0){throw ('Comparison failed. See run.log. Exit='+$code)}
        $result=BRead "$BuilderDir/compare-results.json"
        if($TransportMatrix -and (Test-Path "$($result.Report)/transport-results.csv")){Copy-Item "$($result.Report)/transport-results.csv" (Join-Path $dir ($round.Name.Replace(' ','-')+'-transport.csv'))}
        BSave $result (Join-Path $dir ($round.Name.Replace(' ','-')+'.json'))
    }
    $rows=@(Get-ChildItem $dir -Filter '*.json' | Where-Object Name -NotLike 'request-*' | ForEach-Object {(BRead $_.FullName).Rows})
    $rows|Export-Csv "$dir/results.csv" -NoTypeInformation -Encoding UTF8
    $rows|Select-Object Case,Host,IP,TCP443,TLSVideo,VideoPass,Details|ConvertTo-Html -Head '<meta charset="utf-8"><style>body{font:15px Segoe UI}table{border-collapse:collapse}td,th{padding:8px;border:1px solid #aaa}</style>' -PreContent '<h1>YouTube: two videos, separate CDN results</h1><p>Success on one CDN does not confirm all of YouTube. Startup failures are not network test failures. Previous service state is restored after each round.</p>' | Set-Content "$dir/table.html" -Encoding UTF8
    if($TransportMatrix){
        $matrix=@(Get-ChildItem $dir -Filter '*-transport.csv'|ForEach-Object {
            $video=$_.BaseName
            Import-Csv $_.FullName|Select-Object @{Name='Video';Expression={$video}},Case,Mode,Pass,HTTP,Curl,Bytes,IP,HTTPVersion,Host
        })
        $matrix|Export-Csv "$dir/transport-results.csv" -NoTypeInformation -Encoding UTF8
        $matrix|Select-Object @{Name='Ролик';Expression={$_.Video}},@{Name='Стратегия';Expression={$_.Case}},@{Name='Передача';Expression={$_.Mode}},@{Name='Видео';Expression={if($_.Pass -eq 'True'){'OK'}else{'Сбой'}}},HTTP,Bytes,IP,HTTPVersion,Host|ConvertTo-Html -Head '<meta charset="utf-8"><style>body{font:15px Segoe UI;margin:24px}table{border-collapse:collapse}td,th{padding:7px;border:1px solid #aaa}</style>' -PreContent '<h1>YouTube: TCP / QUIC</h1><p>Два ролика. HTTP3 проверен без возврата на TCP. OK означает получение видеофрагмента; тест временный и не меняет основной состав.</p>'|Set-Content "$dir/table.html" -Encoding UTF8
    }
    if($TransportMatrix -and $sourceHash){
        try{BSaveVerifiedProof $dir $sourceHash}catch{[IO.File]::AppendAllText("$dir/run.log",("Not eligible as default: "+$_.Exception.Message+"`r`n"))}
    }
    ControlState Complete ('Completed. Video transfers passed: '+@($rows|Where-Object VideoPass).Count+'/'+$rows.Count+'. Results: '+$dir)
}catch{ControlState Failed $_.Exception.Message;exit 1}
finally{[void]$mutex.ReleaseMutex();$mutex.Dispose()}

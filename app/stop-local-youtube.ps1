$ErrorActionPreference='Stop'
$data=Join-Path (Split-Path $PSScriptRoot) 'data'
foreach($file in @(Get-ChildItem $data -Filter 'browser-proxy-*.json')){
    $status=Get-Content $file.FullName -Raw -Encoding UTF8|ConvertFrom-Json
    $process=Get-Process -Id ([int]$status.PID) -ErrorAction SilentlyContinue
    if($process -and $process.ProcessName -eq 'node' -and $status.Started -and [math]::Abs(($process.StartTime.ToUniversalTime()-[datetime]::Parse($status.Started).ToUniversalTime()).TotalSeconds) -lt 5){$process.Kill()}
}

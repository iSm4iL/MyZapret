param([string]$Action,[string]$RequestFile)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
try {
    if($RequestFile){& "$PSScriptRoot/builder-action.ps1" -Action $Action -RequestFile $RequestFile}
    else{& "$PSScriptRoot/builder-action.ps1" -Action $Action}
    # Do not inherit a stale native exit code or an ignored cleanup error from the action.
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}

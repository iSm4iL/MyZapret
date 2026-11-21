$ErrorActionPreference='Stop'
$pkg=Split-Path $PSScriptRoot
$status="$pkg/data/repair-run.json";$log="$pkg/reports/full-repair-run.log"
function SaveRun([string]$state,[string]$message){[IO.File]::WriteAllText($status,(@{State=$state;PID=$PID;Time=(Get-Date).ToString('s');Message=$message}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))}
SaveRun 'Running' 'Ожидает отключения VPN, затем проверяет все ветки восстановления'
try{
    & "$PSScriptRoot/builder-action.ps1" -Action RepairAll *> $log
    $proof=Get-Content "$pkg/data/repair-results.json" -Raw -Encoding UTF8|ConvertFrom-Json
    $message=if($proof.Confirmed){'Подтверждено и применено: '+$proof.Recommended+$proof.PacketMethod+$proof.ProxyMode}else{'Подтверждённого решения для автоприменения нет. Результаты протоколов и CDN сохранены.'}
    SaveRun 'Complete' $message
}catch{
    $_|Out-String|Add-Content $log -Encoding UTF8
    SaveRun 'Failed' $_.Exception.Message
    exit 1
}

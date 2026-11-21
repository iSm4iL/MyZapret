$ErrorActionPreference='Stop'
$source=Split-Path $PSScriptRoot
foreach($quicOnly in @($false,$true)){
    $fixture=Join-Path (Split-Path $source) ('data/repair-flow/'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force "$fixture/app","$fixture/data","$fixture/lists","$fixture/strategies","$fixture/docs"|Out-Null
    Copy-Item "$source/*.ps1" "$fixture/app"
    Copy-Item "$source/engine-service.exe" "$fixture/app"
    Copy-Item "$source/tests/fakes.ps1" "$fixture/app/builder-fakes.ps1"
    Copy-Item "$source/../lists/*.txt" "$fixture/lists"
    Copy-Item "$source/../strategies/*.json" "$fixture/strategies"
    $path="$fixture/app/builder-action.ps1"
    $text=[IO.File]::ReadAllText($path).Replace('. "$PSScriptRoot/builder-core.ps1"',('. "$PSScriptRoot/builder-core.ps1"'+"`r`n"+'. "$PSScriptRoot/builder-fakes.ps1"'))
    [IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($true))
    $extra=@'
function BResolveVideo {param($watch,$directory);return [pscustomobject]@{Url='https://localhost/videoplayback';UserAgent='mock'}}
function BRPage {param($directory);return $true}
function BROldCases {return [pscustomobject]@{Name='Mock legacy';Engine='winws';Recipe=$null;Image='old-engine-command'}}
function BRRunCurl {
    param($exe,$arguments,$directory)
    $image=$global:BFServices['myzapret2'].ImagePath
    if($image -match '\s+(?:"([^"]+\.json)"|(\S+\.json))$'){
        $configPath=if($Matches[1]){$Matches[1]}else{$Matches[2]}
        $image=(BRead $configPath).Arguments
    }
    $pass=$image -match 'ip_ttl=5:'
    if($global:RepairQuicOnly){$pass=$pass -and '--http3-only' -in $arguments}
    $file=$arguments[[array]::IndexOf($arguments,'-o')+1]
    if($pass){[IO.File]::WriteAllBytes($file,(New-Object byte[] 65536));return [pscustomobject]@{Code=0;Raw='206|video/mp4|203.0.113.1|0.01|0.02|0.03|2|https://r1.googlevideo.com/videoplayback'}}
    return [pscustomobject]@{Code=28;Raw='000|||0|0|0|0|https://r1.googlevideo.com/videoplayback'}
}
'@
    [IO.File]::WriteAllText("$fixture/app/repair-fakes.ps1",$extra,[Text.UTF8Encoding]::new($true))
    $scriptPath="$fixture/app/repair-youtube.ps1"
    $text=[IO.File]::ReadAllText($scriptPath).Replace('. "$BuilderLab/repair-lib.ps1"',('. "$BuilderLab/repair-lib.ps1"'+"`r`n"+'. "$BuilderLab/repair-fakes.ps1"'))
    [IO.File]::WriteAllText($scriptPath,$text,[Text.UTF8Encoding]::new($true))
    $global:BFServices=$null;$global:RepairQuicOnly=$quicOnly
    & $path -Action Initialize|Out-Null
    . "$fixture/app/builder-core.ps1"
    $model=BWithDonor (BRead $BuilderDraft) 'spotify' '09-disorder-seq';BSave $model $BuilderDraft
    & $path -Action RepairAll|Out-Null
    $proof=BRead "$fixture/data/repair-results.json";$applied=BRead "$fixture/data/active.json"
    if(-not $proof.Complete){throw 'Repair did not complete'}
    if($quicOnly){
        if($proof.Confirmed -or $applied -or $global:BFServices.zapret.Status -ne 'Running'){throw 'QUIC-only result incorrectly applied or original not restored'}
    }else{
        if(-not $proof.Confirmed -or $applied.Model.Selections.youtube.Config -ne '20-fake-ttl5' -or $applied.Model.Selections.spotify.Config -ne '09-disorder-seq'){throw 'Confirmed repair not applied or other donor lost'}
        if(@($proof.Validation|Where-Object Pass).Count -ne 2){throw 'Repair lacked two fresh video confirmations'}
    }
}
'PASS: full repair pipeline, two-video confirmation, preserving other donors, applying confirmed winner and refusing QUIC-only autoapply. Services/network mocked.'

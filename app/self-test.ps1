$ErrorActionPreference='Stop'
. "$PSScriptRoot/builder-core.ps1"
BInitialize
$original=BNewModel '01-split'
$a=BWithDonor $original 'youtube' '05-overlap-681'
$b=BWithDonor $a 'spotify' '09-disorder-seq'
if((BSelections $original).Count -or (BSelections $b).Count -ne 2){throw 'Draft isolation failed'}
$image=BBuild $b
if($image -match '--dpi-desync' -or $image -notmatch 'winws2.exe' -or $image -notmatch 'seqovl=681'){throw 'Engine/profile mismatch'}
if($image.IndexOf('site-youtube.txt') -gt $image.IndexOf('general.txt')){throw 'Scoped profile precedence failed'}
$b.GameFilter=$true;$b.IpsetLoaded=$true
$gameImage=BBuild $b
if($gameImage -notmatch '--filter-tcp 1024-65535' -or $gameImage -notmatch 'game-ipset.txt'){throw 'Game filter missing'}
$onlyIp=BNewModel '01-split';$onlyIp.IpsetLoaded=$true
if((BBuild $onlyIp) -notmatch '--ipset '){throw 'IPSet must also work without game mode'}
$overlap=BWithDonor (BWithDonor $original 'google' '01-split') 'youtube' '09-disorder-seq'
if((BBuild $overlap) -notmatch '--hostlist-exclude-domains youtube'){throw 'Google donor can shadow YouTube API domains'}
try{BSetVideo 'https://example.com/videoplayback';throw 'Invalid media host was accepted'}catch{if($_.Exception.Message -notlike 'Нужна ссылка*'){throw}}
$native=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if($native){
    foreach($donor in Get-Configs){
        $all=BNewModel $donor
        foreach($g in $SiteGroups.Keys){$all=BWithDonor $all $g $donor}
        BValidate (BBuild $all)
    }
    BValidate $gameImage
    BValidate (BBuild $onlyIp)
    'PASS: native Lua initialization for all 10 recipes x 17 services and game/IPSet; interception disabled.'
}else{'Native checks need admin; model checks only.'}
$frozen=BFreeze $gameImage (Join-Path $BuilderDir ('selftest/'+[guid]::NewGuid().ToString('N')))
if($frozen -match [regex]::Escape($Lists+'\')){throw 'Unfrozen list'}
'PASS: winws2 model, donor isolation, precedence, game flags, frozen lists.'

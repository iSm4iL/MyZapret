$ErrorActionPreference='Stop'
$pkg=Split-Path $PSScriptRoot
$recipes=[ordered]@{
 '01-split'=@{Title='Split';Origin='Our original zapret2';Tls=@('--lua-desync multisplit:pos=1,midsld');QuicRepeats=6}
 '02-fake-ts'=@{Title='Fake + split TS';Origin='Our original zapret2';Tls=@('--lua-desync fake:blob=fake_default_tls:tcp_ts=-1000:repeats=6','--lua-desync fakedsplit:pos=1:tcp_ts=-1000');QuicRepeats=6}
 '03-fake-seq'=@{Title='Fake + split SEQ';Origin='Our original zapret2';Tls=@('--lua-desync fake:blob=fake_default_tls:tcp_seq=-10000:repeats=6','--lua-desync fakedsplit:pos=1:tcp_seq=-10000');QuicRepeats=6}
 '04-disorder-md5'=@{Title='Fake MD5 + disorder';Origin='Our original zapret2';Tls=@('--lua-desync fake:blob=fake_default_tls:tcp_md5:repeats=6:tls_mod=rnd,dupsid,sni=www.google.com','--lua-desync multidisorder:pos=1,midsld');QuicRepeats=6}
 '05-overlap-681'=@{Title='Overlap 681';Origin='GANWO general: multisplit/seqovl=681, adapted to Lua';Tls=@('--lua-desync multisplit:pos=1:seqovl=681:seqovl_pattern=fake_default_tls');QuicRepeats=6}
 '06-overlap-568'=@{Title='Overlap 568';Origin='GANWO general: multisplit/seqovl=568, adapted to Lua';Tls=@('--lua-desync multisplit:pos=1:seqovl=568:seqovl_pattern=fake_default_tls');QuicRepeats=11}
 '07-hostfake-ts'=@{Title='Host fake TS';Origin='GANWO ALT13 hostfakesplit idea, adapted to Lua';Tls=@('--lua-desync hostfakesplit:host=www.google.com:tcp_ts=-1000');QuicRepeats=11}
 '08-double-fake'=@{Title='Double fake + split';Origin='GANWO double-fake idea; our Lua variant';Tls=@('--lua-desync fake:blob=fake_default_tls:tcp_seq=-10000:repeats=6:tls_mod=rnd,dupsid,sni=www.google.com','--lua-desync fake:blob=fake_default_tls:tcp_ts=-1000:repeats=6:tls_mod=rnd,dupsid,sni=www.microsoft.com','--lua-desync multisplit:pos=1,midsld');QuicRepeats=11}
 '09-disorder-seq'=@{Title='Disorder SEQ';Origin='Our Lua variant for CDN';Tls=@('--lua-desync fake:blob=fake_default_tls:tcp_seq=-10000:repeats=8','--lua-desync multidisorder:pos=1,midsld');QuicRepeats=8}
 '10-hostfake-seq'=@{Title='Host fake SEQ';Origin='Our Lua variant for CDN';Tls=@('--lua-desync hostfakesplit:host=www.google.com:tcp_seq=-10000');QuicRepeats=8}
}
foreach($id in $recipes.Keys){
    $recipes[$id]|ConvertTo-Json -Depth 5|Set-Content "$pkg/strategies/$id.json" -Encoding UTF8
    $bat="@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0app\start-strategy.ps1`" -Strategy `"$id`"`r`n"
    [IO.File]::WriteAllText("$pkg/general ($id).bat",$bat,[Text.Encoding]::ASCII)
}
. "$PSScriptRoot/builder-core.ps1"
$hosts=@($BuilderCatalog.Values|ForEach-Object {$_.Domains})
foreach($file in @('list-general.txt','list-general-user.txt','list-google.txt')){$hosts+=Get-Content "$Lists/$file"|Where-Object {$_ -and $_ -notmatch '^\s*#'}}
[IO.File]::WriteAllLines("$Lists/general.txt",[string[]]@($hosts|Sort-Object -Unique),[Text.UTF8Encoding]::new($false))
BInitialize
'Prepared 10 winws2 recipes and root strategy launchers.'

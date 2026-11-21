# Core functions for the zapret tool. Dot-sourced by zapret_tool.ps1 and zapret_auto.ps1.
# This file lives in <zapret folder>\zapret_tool\ ; configs and lists are in <zapret folder>.
$Tool    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root    = Split-Path -Parent $Tool
$Lists   = Join-Path $Root 'lists'
$Store   = Join-Path $Tool 'store'
$State   = Join-Path $Tool 'state.json'
$Applied = Join-Path $Tool 'applied.json'
$Parts   = Join-Path $Store 'parts.json'
$Log     = Join-Path $Tool 'tool.log'
$GfFlag  = Join-Path $Root 'utils\game_filter.enabled'
$TestDir = Join-Path $Root 'utils\test results'
$VpnLog  = 'C:\ProgramData\VPNUS\service.log'
$SvcKey  = 'HKLM:\SYSTEM\CurrentControlSet\Services\zapret'
$TaskName = 'zapret-auto-mode'
# Game processes that switch game filter + ipset on (PUBG and WarDogs)
$GameProcs = @('TslGame')
$WdProcs = @('WardogsClient-Win64-Shipping', 'WardogsLauncher-Shipping')
function Get-WdRunning { [bool](Get-Process -Name $WdProcs -ErrorAction SilentlyContinue) }
function Get-GameRunning { [bool](Get-Process -Name $GameProcs -ErrorAction SilentlyContinue) }

# parts system: slots and the group each slot serves
$Slots     = @('quic', 'discord_udp', 'discord_tcp', 'google', 'general_tcp')
$GroupSlot = @{ youtube = 'google'; discord = 'general_tcp'; general = 'general_tcp' }
$ProbeEvery = 180
$DefaultConfig = 'general (SIMPLE FAKE)'

function L([string]$m) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" | Out-File -FilePath $Log -Append -Encoding UTF8 }

function Load-Json([string]$path, $default) {
    if (Test-Path $path) { try { return (Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch {} }
    return $default
}
function Save-Json($obj, [string]$path) { $obj | ConvertTo-Json -Depth 5 | Out-File -FilePath $path -Encoding UTF8 }

function Get-State {
    return (Load-Json $State ([pscustomobject]@{ config = $DefaultConfig; gf = $false; ipset = $false; auto = $true; parts = $false }))
}
function Get-Applied { return (Load-Json $Applied ([pscustomobject]@{ config = ''; gf = $false; ipset = $false; parts = $false; choice = '' })) }
function Get-Parts-State {
    return (Load-Json $Parts ([pscustomobject]@{ choice = @(0, 0, 0, 0, 0); fails = [pscustomobject]@{ youtube = 0; discord = 0; general = 0 } }))
}
function Get-Configs { Get-ChildItem $Root -Filter 'general*.bat' | Sort-Object Name | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) } }

function Get-Effective($st, [bool]$gameRunning) {
    if ([bool]$st.auto) { return [pscustomobject]@{ gf = $gameRunning; ipset = $gameRunning } }
    return [pscustomobject]@{ gf = [bool]$st.gf; ipset = [bool]$st.ipset }
}

function Vpn-Connected {
    $last = Get-Content $VpnLog -Tail 300 -Encoding UTF8 -ErrorAction SilentlyContinue |
        Where-Object { $_ -match '\[tunnel\] (dis)?connected\s*$' } | Select-Object -Last 1
    return ($last -match '\] connected\s*$')
}

# ---- profile handling -------------------------------------------------------
function Get-Profiles([string]$cfgName, [bool]$gf) {
    $bat = Join-Path $Root ($cfgName + '.bat')
    if (-not (Test-Path -LiteralPath $bat)) { return $null }
    $raw = (Get-Content -LiteralPath $bat -Raw -Encoding UTF8) -replace '\^\r?\n', ' ' -replace '\^!', '!' -replace "`r", ' '
    $m = [regex]::Match($raw, 'winws\.exe"?\s+(.+)')
    if (-not $m.Success) { return $null }
    $gfv = if ($gf) { '1024-65535' } else { '12' }
    $s = $m.Groups[1].Value -replace '%BIN%', ($Root + '\bin\') -replace '%LISTS%', ($Root + '\lists\') `
            -replace '%GameFilterTCP%', $gfv -replace '%GameFilterUDP%', $gfv
    $tokens = @([regex]::Matches($s, '(?:[^\s"]|"[^"]*")+') | ForEach-Object { $_.Value })
    $header = New-Object System.Collections.ArrayList
    $profiles = New-Object System.Collections.ArrayList
    $cur = New-Object System.Collections.ArrayList
    foreach ($t in $tokens) {
        if ($t -match '^--wf-') { [void]$header.Add(($t -replace '^(--[^=]+)=', '$1 ')); continue }
        if ($t -eq '--new') { [void]$profiles.Add(@($cur)); $cur = New-Object System.Collections.ArrayList; continue }
        [void]$cur.Add($t)
    }
    if ($cur.Count -gt 0) { [void]$profiles.Add(@($cur)) }
    return [pscustomobject]@{ Header = ($header -join ' '); Profiles = $profiles }
}

function Get-Class($p) {
    $j = ($p -join ' ')
    if ($j -match 'list-google\.txt') { return 'google' }
    if ($j -match 'discord\.media') { return 'discord_tcp' }
    if ($j -match 'filter-l7=discord') { return 'discord_udp' }
    if ($j -match 'list-general\.txt' -and $j -match 'filter-udp=443') { return 'quic' }
    if ($j -match 'list-general\.txt' -and $j -match 'filter-tcp=80,443') { return 'general_tcp' }
    return $null
}

function Conv-Profile($p) { (($p | ForEach-Object { $_ -replace '^(--[^=]+)=', '$1 ' }) -join ' ') }

# Whole single config (parts system off)
function Build-ImagePath([string]$cfgName, [bool]$gf) {
    $pr = Get-Profiles $cfgName $gf
    if (-not $pr) { return $null }
    $segs = New-Object System.Collections.ArrayList
    foreach ($p in $pr.Profiles) { [void]$segs.Add((Conv-Profile $p)) }
    return ('"' + $Root + '\bin\winws.exe" ' + $pr.Header + ' ' + ($segs -join ' --new ')) -replace '\s+', ' '
}

# names: one config name per slot (in $Slots order); ipset/game profiles come from the base config
function Build-Composite([string[]]$names, [bool]$gf, [string]$base) {
    $bp = Get-Profiles $base $gf
    if (-not $bp) { return $null }
    $pick = @{}
    for ($i = 0; $i -lt $Slots.Count; $i++) {
        $cp = Get-Profiles $names[$i] $gf
        if (-not $cp) { return $null }
        $found = $null
        foreach ($p in $cp.Profiles) { if ((Get-Class $p) -eq $Slots[$i]) { $found = $p; break } }
        if (-not $found) { return $null }
        $pick[$Slots[$i]] = $found
    }
    $ordered = New-Object System.Collections.ArrayList
    foreach ($s in $Slots) { [void]$ordered.Add($pick[$s]) }
    foreach ($p in $bp.Profiles) { if (-not (Get-Class $p)) { [void]$ordered.Add($p) } }
    $segs = New-Object System.Collections.ArrayList
    foreach ($p in $ordered) { [void]$segs.Add((Conv-Profile $p)) }
    return ('"' + $Root + '\bin\winws.exe" ' + $bp.Header + ' ' + ($segs -join ' --new ')) -replace '\s+', ' '
}

# ---- per-person ranking from the latest standard test ---------------------
function Get-LatestStdResults {
    if (-not (Test-Path $TestDir)) { return $null }
    Get-ChildItem $TestDir -Filter 'test_results_*' -ErrorAction SilentlyContinue |
        Where-Object { -not ((Get-Content $_.FullName -TotalCount 1 -Encoding UTF8) -match 'Type: dpi') } |
        Sort-Object LastWriteTime | Select-Object -Last 1
}

# returns @{ config -> @{ google; discord; other } } from the newest standard test, or $null
function Get-TestScores {
    $f = Get-LatestStdResults
    if (-not $f) { return $null }
    $scores = @{}
    $cur = $null
    foreach ($line in (Get-Content $f.FullName -Encoding UTF8)) {
        if ($line -match '^Config: (.+?)\.bat \(Type') { $cur = $matches[1]; $scores[$cur] = @{ google = 0; discord = 0; other = 0 }; continue }
        if ($cur -and $line -match '^\s+(\S+)\s*:\s*(HTTP:.*?)\|') {
            $name = $matches[1]
            $ok = ([regex]::Matches($matches[2], 'OK')).Count
            $grp = if ($name -match '^(YouTube|Google)') { 'google' } elseif ($name -match '^Discord') { 'discord' } else { 'other' }
            $scores[$cur][$grp] += $ok
        }
    }
    return $scores
}

# ranking of configs for one slot, best first. Without test data: the saved default order (all configs).
function Get-SlotRanking([string]$slot) {
    $scores = Get-TestScores
    $usable = @(Get-Configs | Where-Object { Get-Profiles $_ $false } | Where-Object { $_ -ne $null })
    $usable = @($usable | Where-Object { $p = Get-Profiles $_ $false; ($p.Profiles | ForEach-Object { Get-Class $_ }) -contains $slot })
    $main = [string](Get-State).config
    if (-not $scores -or $usable.Count -eq 0) {
        return @(@($main) + @($usable | Where-Object { $_ -ne $main }))
    }
    $value = {
        param($c)
        $s = $scores[$c]
        if (-not $s) { return -1 }
        switch ($slot) {
            'quic'         { return [int]$s.google }
            'google'       { return [int]$s.google }
            'discord_udp'  { return [int]$s.discord }
            'discord_tcp'  { return [int]$s.discord }
            'general_tcp'  { return [int]$s.other + [int]$s.discord }
        }
    }
    $rank = $usable | ForEach-Object { [pscustomobject]@{ name = $_; v = (& $value $_); total = $(if ($scores[$_]) { [int]$scores[$_].google + [int]$scores[$_].discord + [int]$scores[$_].other } else { 0 }) } }
    $list = @($rank | Sort-Object @{Expression = 'v'; Descending = $true}, @{Expression = 'total'; Descending = $true}, @{Expression = 'name'} | ForEach-Object { $_.name })
    if ($list -contains $main) { $list = @(@($main) + @($list | Where-Object { $_ -ne $main })) }
    return $list
}

function Get-SlotNames($ps) {
    $names = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $Slots.Count; $i++) {
        $rk = @(Get-SlotRanking $Slots[$i])
        $idx = [int]@($ps.choice)[$i] % [Math]::Max(1, $rk.Count)
        [void]$names.Add($rk[$idx])
    }
    return $names.ToArray()
}

function Get-ChoiceString($ps) { (@($ps.choice) -join ',') }

# ---- applying -------------------------------------------------------------
function Set-Ipset([bool]$loaded) {
    $src = if ($loaded) { Join-Path $Store 'ipset-loaded.txt' } else { Join-Path $Store 'ipset-none.txt' }
    $dst = Join-Path $Lists 'ipset-all.txt'
    if (-not (Test-Path $dst) -or (Get-Item $dst).Length -ne (Get-Item $src).Length) { Copy-Item $src $dst -Force }
}
function Set-GameFilter([bool]$on) {
    New-Item -ItemType Directory -Force -Path (Split-Path $GfFlag) | Out-Null
    if ($on) { [IO.File]::WriteAllText($GfFlag, "all`r`n", (New-Object Text.UTF8Encoding($false))) }
    elseif (Test-Path $GfFlag) { Remove-Item $GfFlag -Force }
}

# Apply current settings. Restarts zapret only if it is running.
function Add-WdProfile([string]$img) {
    $extra = (Get-Content (Join-Path $Store 'wardogs_extra.txt') -Raw -Encoding UTF8).Trim().Replace('{TOOL}', $Tool)
    $img = $img -replace '(--wf-udp \S+)', '$1,4192,50008'
    return ($img + ' --new ' + $extra) -replace '\s+', ' '
}

function Add-SpotifyProfile([string]$img) {
    $extra = (Get-Content (Join-Path $Store 'spotify_extra.txt') -Raw -Encoding UTF8).Trim().Replace('{TOOL}', $Tool)
    return ($img + ' --new ' + $extra) -replace '\s+', ' '
}

function Apply-Config([string]$cfg, [bool]$gf, [bool]$ipset, [bool]$wd = $false) {
    Set-Ipset $ipset
    Set-GameFilter $gf
    $st = Get-State
    $ps = Get-Parts-State
    $partsOn = [bool]$st.parts
    if ($partsOn) {
        $names = @(Get-SlotNames $ps)
        $img = Build-Composite $names $gf $cfg
    } else { $img = Build-ImagePath $cfg $gf }
    if (-not $img) { L "cannot build settings for '$cfg' (parts=$partsOn)"; return $false }
    if ($wd) { $img = Add-WdProfile $img }
    $img = Add-SpotifyProfile $img
    if(Test-Path (Join-Path $Store 'site-overrides.json')) {
        . (Join-Path $Tool 'site_fragments.ps1')
        $img = Add-SiteProfiles $img (Get-SiteSelections) $gf
    }
    $img = ConvertTo-ZapretServiceCommand $img (Join-Path $Store 'service-configs')
    $svc = Get-Service zapret -ErrorAction SilentlyContinue
    if ($svc) { Set-ZapretServiceCommand 'zapret' $img }
    else { New-Service -Name zapret -BinaryPathName $img -DisplayName zapret -StartupType Automatic -Description 'Zapret DPI bypass software' | Out-Null }
    reg.exe add 'HKLM\System\CurrentControlSet\Services\zapret' /v zapret-discord-youtube /t REG_SZ /d $cfg /f | Out-Null
    if ($svc -and (Get-Service zapret).Status -eq 'Running') { Restart-Service zapret -Force }
    Save-Json ([pscustomobject]@{ config = $cfg; gf = $gf; ipset = $ipset; parts = $partsOn; choice = (Get-ChoiceString $ps); wd = $wd }) $Applied
    L "applied: config=$cfg gameFilter=$gf ipsetLoaded=$ipset parts=$partsOn choice=$(Get-ChoiceString $ps)"
    return $true
}

function Sync-Now {
    $st = Get-State
    $g = Get-GameRunning
    $e = Get-Effective $st $g
    Apply-Config $st.config ([bool]$e.gf) ([bool]$e.ipset) (Get-WdRunning) | Out-Null
}

# ---- parts: probing and swapping ------------------------------------------
function Probe([string]$url, [int64]$minBytes) {
    $o = curl.exe -s -m 10 -o NUL -w '%{http_code} %{size_download}' $url 2>$null
    $p = @($o -split ' ')
    if ($p.Count -lt 2) { return $false }
    $code = $p[0] -as [int]; $size = $p[1] -as [int64]
    return ($code -ge 200 -and $code -lt 400 -and $size -ge $minBytes)
}
function Probe-Groups {
    @{
        control = Probe 'https://www.google.com/' 0
        youtube = ((Probe 'https://www.youtube.com/' 150000) -and (Probe 'https://i.ytimg.com/vi/aqz-KE-bpKQ/hqdefault.jpg' 25000))
        discord = Probe 'https://discord.com/' 0
        general = Probe 'https://www.reddit.com/' 0
    }
}

# one probe round: a failing group moves only its own part to the next config in that slot's ranking
function Parts-Step {
    $pst = Get-Parts-State
    $res = Probe-Groups
    if (-not $res.control) { L 'parts: control site down, no swaps'; return }
    $changed = $false
    foreach ($g in 'youtube', 'discord', 'general') {
        if ($res[$g]) { $pst.fails.$g = 0; continue }
        $pst.fails.$g = [int]$pst.fails.$g + 1
        if ($pst.fails.$g -ge 2) {
            $slot = $GroupSlot[$g]
            $i = [array]::IndexOf($Slots, $slot)
            $rk = @(Get-SlotRanking $slot)
            $pst.choice[$i] = ([int]$pst.choice[$i] + 1) % [Math]::Max(1, $rk.Count)
            $pst.fails.$g = 0
            $changed = $true
            L "parts: $g failing -> slot $slot now '$($rk[$pst.choice[$i]])' (rank $($pst.choice[$i] + 1) of $($rk.Count))"
        }
    }
    Save-Json $pst $Parts
    if ($changed) { Sync-Now }
}








. "$PSScriptRoot/service-command.ps1"

# ===================== INVENTORY: data collectors =====================
function Tm($name, [scriptblock]$b) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { $r = & $b }
    catch { Write-Log ERROR "$name collector failed: $($_.Exception.Message)"; $r = $NO }    # one broken collector must not stop the inventory
    Write-Host ('  ({0}: {1:N1}s)' -f $name, $sw.Elapsed.TotalSeconds) -ForegroundColor DarkGray
    $r
}

function Get-UserProfileDirs {
    $r = @()
    try { $r += (Get-ChildItem 'C:\Users' -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) } catch { Write-Log DEBUG "profiles: cannot list C:\Users: $($_.Exception.Message)" }
    $r += 'C:\Windows\ServiceProfiles\LocalService', 'C:\Windows\ServiceProfiles\NetworkService', 'C:\Windows\System32\config\systemprofile'
    $r | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
}

# shared read (works even if the app keeps the file open), BOM / UTF-8 / cp1251 aware
function Read-TextSmart($path) {
    $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite,Delete')
    try { $ms = New-Object IO.MemoryStream; $fs.CopyTo($ms); $b = $ms.ToArray() } finally { $fs.Dispose() }
    if ($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) { return [Text.Encoding]::Unicode.GetString($b).TrimStart([char]0xFEFF) }
    if ($b.Length -ge 2 -and $b[0] -eq 0xFE -and $b[1] -eq 0xFF) { return [Text.Encoding]::BigEndianUnicode.GetString($b).TrimStart([char]0xFEFF) }
    $t = [Text.Encoding]::UTF8.GetString($b)
    if ($t.Contains([string][char]0xFFFD)) { $t = [Text.Encoding]::GetEncoding(1251).GetString($b) }
    $t.TrimStart([char]0xFEFF)
}

function Get-Uninstall {
    if ($script:UninstallCache) { return $script:UninstallCache }
    $k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $script:UninstallCache = @(Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName })
    $script:UninstallCache
}

# ---- is the product present at all? (tells "not installed" from "installed, but its ID was not found") ----
function Test-AppPresent([string]$pat) {
    $why = @()
    try { $x = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $pat } | Select-Object -First 1; if ($x) { $why += "process: $($x.Name)" } } catch { }
    try { $x = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match $pat } | Select-Object -First 1; if ($x) { $why += "service: $($x.PSChildName)" } } catch { }
    try { $x = Get-Uninstall | Where-Object { $_.DisplayName -match $pat } | Select-Object -First 1; if ($x) { $why += "installed: $($x.DisplayName)" } } catch { }
    $why
}

# executables of a product: Seen = anywhere (running copy, portable), Installed = Program Files / uninstall entry / config.json (safe to call with a CLI switch)
function Get-AppExePaths([string]$procPat, [string]$uninstPat, [string[]]$known, [string]$exeName, [string]$cfgKey) {
    $seen = New-Object Collections.ArrayList; $inst = New-Object Collections.ArrayList
    try { foreach ($p in @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $procPat })) { try { if ($p.Path) { [void]$seen.Add([string]$p.Path) } } catch { } } } catch { }
    foreach ($k in $known) { if ($k) { [void]$inst.Add($k) } }
    try { foreach ($u in @(Get-Uninstall | Where-Object { $_.DisplayName -match $uninstPat })) { if ($u.InstallLocation) { [void]$inst.Add((Join-Path ([string]$u.InstallLocation).Trim('"') $exeName)) } } } catch { }
    foreach ($x in @(Cfg $cfgKey @())) { if ($x) { [void]$inst.Add([string]$x) } }
    $ok = { param($l) @($l | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -Unique) }
    [pscustomobject]@{ Installed = (& $ok $inst); Seen = (& $ok (@($inst) + @($seen))) }
}

function Get-ProgramFilesPaths([string]$rel) {
    $r = @()
    foreach ($b in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) { if ($b) { $r += (Join-Path $b $rel) } }
    if ($env:LOCALAPPDATA) { $r += (Join-Path $env:LOCALAPPDATA ('Programs\' + $rel)) }
    $r
}

# ---- AnyDesk: ID is "ad.anynet.id=NNN" in system.conf (older builds: ad.anydesk.id). Portable copies keep it in %APPDATA%\AnyDesk too ----
function Get-AnyDeskId {
    $files = @()
    if ($env:ProgramData) { $files += Join-Path $env:ProgramData 'AnyDesk\system.conf' }
    if ($env:APPDATA)     { $files += Join-Path $env:APPDATA 'AnyDesk\system.conf' }
    foreach ($d in (Get-UserProfileDirs)) { $files += Join-Path $d 'AppData\Roaming\AnyDesk\system.conf' }
    foreach ($d in @(Cfg 'anyDesk.extraConfigDirs' @())) { if ($d) { $files += Join-Path ([string]$d) 'system.conf' } }     # config.json: non-standard config folders
    foreach ($f in ($files | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $f)) { Write-Log DEBUG "anydesk: no file $f"; continue }
        try {
            $m = [regex]::Match((Read-TextSmart $f), '(?m)^\s*ad\.(?:anynet|anydesk)\.id\s*=\s*(\d+)')
            if ($m.Success) { $script:Src.AnyDesk = $f; Write-Log DEBUG "anydesk: id found in $f"; return $m.Groups[1].Value }
            Write-Log DEBUG "anydesk: $f exists, but has no ad.anynet.id line"
        } catch { Write-Log DEBUG "anydesk: cannot read ${f}: $($_.Exception.Message)" }
    }
    # no config: ask an INSTALLED copy (AnyDesk.exe --get-id)
    if (Cfg 'features.anyDeskCli' $true) {
        $ex = Get-AppExePaths 'AnyDesk' '^AnyDesk' @(Get-ProgramFilesPaths 'AnyDesk\AnyDesk.exe') 'AnyDesk.exe' 'anyDesk.extraPaths'
        foreach ($exe in @($ex.Installed | Select-Object -First 2)) {
            $x = Invoke-External $exe '--get-id' ([int](Cfg 'timeouts.anyDeskCliSec' 8))
            Write-Log DEBUG "anydesk: cli $exe --get-id exit=$($x.ExitCode) timeout=$($x.TimedOut) error=$($x.Error)"
            $m = [regex]::Match($x.Stdout, '(?m)^\s*(\d{6,})\s*$')
            if ($m.Success) { $script:Src.AnyDesk = "$exe --get-id (CLI)"; return $m.Groups[1].Value }
        }
    }
    $why = @(Test-AppPresent '^AnyDesk')
    try {   # portable copy lying around (desktop / downloads), not running
        foreach ($d in (Get-UserProfileDirs)) { foreach ($sub in 'Desktop', 'Downloads') {
            $x = Get-ChildItem (Join-Path $d $sub) -Filter 'AnyDesk*.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($x) { $why += "portable exe: $($x.FullName)" }
        } }
    } catch { }
    if ($why.Count) {
        $script:Src.AnyDesk = 'present, but no ID found: ' + ($why -join ' ; ')
        Write-Log WARN 'AnyDesk is present, but its ID was not found (start it once, or add its config folder to config.json: anyDesk.extraConfigDirs)'
        return $NoId
    }
    Write-Log DEBUG 'anydesk: not installed, ID not found in any known location'
    return $NO
}

# ---- HopToDesk (RustDesk-based): id = '...' in HopToDesk*.toml ----
function Find-HopId($dir) {
    $tomls = @(Get-ChildItem $dir -Recurse -Depth 3 -Filter '*.toml' -File -Force -ErrorAction SilentlyContinue |
               Sort-Object @{ e = { if ($_.Name -match '^HopToDesk\.toml$') { 0 } else { 1 } } }, Name)
    foreach ($f in $tomls) {
        try {
            $m = [regex]::Match((Read-TextSmart $f.FullName), '(?m)^\s*id\s*=\s*[''"]([A-Za-z0-9]+)[''"]')
            if ($m.Success) { return [pscustomobject]@{ Id = $m.Groups[1].Value; File = $f.FullName } }
        } catch { Write-Log DEBUG "hop: cannot read $($f.FullName): $($_.Exception.Message)" }
    }
    $null
}

function Get-HopToDeskId {
    $log = New-Object Collections.ArrayList
    $note = { param($m) [void]$log.Add($m); Write-Log DEBUG "hop: $m" }
    $dirs = @()
    if (-not $NoHopCli) {   # HopToDesk 1.46.x keeps no plain ID in *.toml: ask the app itself (HopToDesk.exe --get-id)
        $ex = Get-AppExePaths 'HopToDesk' '^HopToDesk' @(Get-ProgramFilesPaths 'HopToDesk\HopToDesk.exe') 'HopToDesk.exe' 'hopToDesk.extraPaths'
        if ($ex.Installed.Count) {
            $to = [int](Cfg 'timeouts.hopToDeskCliSec' 8)
            foreach ($exe in @($ex.Installed | Select-Object -First 2)) {
                $x = Invoke-External $exe '--get-id' $to
                & $note "cli $exe --get-id exit=$($x.ExitCode) timeout=$($x.TimedOut) error=$($x.Error)"
                $m = [regex]::Match($x.Stdout, '(?m)^\s*(\d{6,})\s*$')
                if ($m.Success) { $script:Src.Hop = "$exe --get-id (CLI)"; return $m.Groups[1].Value }
                & $note 'cli returned no numeric ID'
            }
        } else { & $note 'HopToDesk.exe not found (Program Files, per-user install, uninstall entries, config.json)' }
    }

    if ($env:APPDATA)     { $dirs += Join-Path $env:APPDATA 'HopToDesk' }
    if ($env:ProgramData) { $dirs += Join-Path $env:ProgramData 'HopToDesk' }
    foreach ($d in (Get-UserProfileDirs)) { $dirs += Join-Path $d 'AppData\Roaming\HopToDesk'; $dirs += Join-Path $d 'AppData\Local\HopToDesk' }
    foreach ($d in ($dirs | Select-Object -Unique)) {
        $ex2 = Test-Path $d; & $note "dir $d exists=$ex2"
        if (-not $ex2) { continue }
        $r = Find-HopId $d
        if ($r) { $script:Src.Hop = $r.File; return $r.Id }
        & $note '   no id in *.toml'
    }

    # service profiles are ACL-protected: copy *.toml with backup privilege (robocopy /B), then parse the copy.
    # /B needs an elevated session, without it robocopy only fails, so it is skipped.
    if (Test-IsAdmin) {
        $tmpRoot = Join-Path $env:TEMP ('h2d_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $rto = [int](Cfg 'timeouts.robocopySec' 30)
        try {
            foreach ($s in 'C:\Windows\ServiceProfiles\LocalService', 'C:\Windows\ServiceProfiles\NetworkService', 'C:\Windows\System32\config\systemprofile') {
                $src = Join-Path $s 'AppData\Roaming\HopToDesk'
                $dst = Join-Path $tmpRoot (Split-Path $s -Leaf)
                try {
                    $x = Invoke-External 'robocopy' ('"{0}" "{1}" *.toml /E /B /R:0 /W:0 /NP /NJH /NJS /NFL /NDL' -f $src, $dst) $rto
                    & $note "robocopy /B $src exit=$($x.ExitCode) timeout=$($x.TimedOut) $($x.Error)"
                    if (Test-Path $dst) {
                        $r = Find-HopId $dst
                        if ($r) { $script:Src.Hop = $r.File.Replace($dst, $src) + ' (backup-mode copy)'; return $r.Id }
                        & $note '   copied, but no id in *.toml'
                    }
                } catch { & $note "robocopy error: $($_.Exception.Message)" }
            }
        } finally { Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue }
    } else { & $note 'not elevated: service profiles (robocopy /B) skipped' }

    $why = @(Test-AppPresent 'HopToDesk')
    if ($why.Count) {
        $script:Src.Hop = 'present, but no ID found: ' + ($why -join ' ; ')
        Write-Host '  HopToDesk is present, but its ID was not found; search log: Raports\_hop_search.txt' -ForegroundColor Yellow
        foreach ($w in $why) { [void]$log.Add($w) }
        try { $log | Out-File (Join-Path $OutDir '_hop_search.txt') -Encoding utf8 } catch { }
        return $NoId
    }
    return $NO
}

# ---- Deep Freeze / Shadow Defender: services, processes, drivers (both are in the Services registry key), uninstall entries, known folders ----
# Deep Freeze patterns do NOT use the bare word "Faronics": the vendor has other products (that would be a false "Deep Freeze: on").
# Presence of the product is detected; frozen / thawed state cannot be read reliably, so it is not claimed.
function Get-FreezeStatus {
    $on   = [string](Cfg 'freeze.enabledText' (U '\u0412\u043a\u043b\u044e\u0447\u0435\u043d\u043e'))
    $excl = 'MiniTool|ShadowMaker|ShadowCopy|Volume Shadow|SDRSVC|SDXHelper'     # look-alikes that are NOT freeze software
    $defs = [ordered]@{
        'Deep Freeze'     = @{ Pat = 'Deep ?Freeze|DFServ|DF5Serv|DepFrz|DeepFrz|FrzState2k|DFRTSvc|Persi0'
                               Paths = @('C:\Persi0', 'C:\Program Files\Faronics\Deep Freeze*', 'C:\Program Files (x86)\Faronics\Deep Freeze*',
                                         (Join-Path $env:windir 'SysWOW64\DFServ.exe'), (Join-Path $env:windir 'System32\DFServ.exe'),
                                         (Join-Path $env:windir 'System32\drivers\DepFrz.sys')) }
        'Shadow Defender' = @{ Pat = 'Shadow ?Defender|ShadowDefender|SDCoreService|SDDrv'
                               Paths = @('C:\Program Files\Shadow Defender', 'C:\Program Files (x86)\Shadow Defender') }
    }
    foreach ($d in @(Cfg 'freeze.disableBuiltin' @())) { $defs.Remove([string]$d) }       # config.json: drop a built-in product
    foreach ($xp in @(Cfg 'freeze.extraProducts' @())) {                                  # config.json: add your own product
        if ($xp.name -and $xp.pattern) { $defs[[string]$xp.name] = @{ Pat = [string]$xp.pattern; Paths = @($xp.paths | Where-Object { $_ }) } }
    }
    $ex2 = [string](Cfg 'freeze.excludePattern' ''); if ($ex2) { $excl = "$excl|$ex2" }
    $procs = @(); try { $procs = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) } catch { Write-Log DEBUG "freeze: Get-Process failed: $($_.Exception.Message)" }
    $svcs  = @(); try { $svcs = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction SilentlyContinue | ForEach-Object { "$($_.PSChildName) | $($_.GetValue('DisplayName')) | $($_.GetValue('ImagePath'))" }) } catch { Write-Log DEBUG "freeze: cannot read the Services registry key: $($_.Exception.Message)" }   # services + drivers straight from the registry (fast)
    $apps  = @(Get-Uninstall | ForEach-Object { "$($_.DisplayName) | $($_.Publisher)" })

    $res = @(); $why = @()
    foreach ($prod in $defs.Keys) {
        $pat = $defs[$prod].Pat; $ev = @()
        $x = $procs | Where-Object { $_ -match $pat -and $_ -notmatch $excl } | Select-Object -First 1; if ($x) { $ev += "process: $x" }
        $x = $svcs  | Where-Object { $_ -match $pat -and $_ -notmatch $excl } | Select-Object -First 1; if ($x) { $ev += "service/driver: $x" }
        $x = $apps  | Where-Object { $_ -match $pat -and $_ -notmatch $excl } | Select-Object -First 1; if ($x) { $ev += "installed: $x" }
        foreach ($p in $defs[$prod].Paths) { if (Test-Path $p -ErrorAction SilentlyContinue) { $ev += "path: $p"; break } }
        if (-not $ev.Count) { Write-Log DEBUG "freeze: $prod - no evidence (processes=$($procs.Count) services=$($svcs.Count) apps=$($apps.Count))"; continue }
        $name = $prod
        if ($prod -eq 'Deep Freeze') {
            $ed = [regex]::Match(($apps -join "`n"), 'Deep Freeze\s+(Standard|Enterprise|Server)')
            $name = if ($ed.Success) { $ed.Value -replace '\s+', ' ' } else { 'Deep Freeze Standard' }
        }
        $res += "$name $([char]0x2014) $on"
        $why += "$prod <- " + ($ev -join ' ; ')
        Write-Log DEBUG ("freeze: $prod - " + ($ev -join ' ; '))
    }
    if ($res.Count) { $script:Src.Freeze = ($why -join ' || '); return ($res -join '; ') }
    return $NO
}

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

# ---- compatibility signatures ----
# The ONLY place with product-specific technical identifiers (folder / file / service / process names, CLI switch).
# They are used read-only to recognise software that is ALREADY installed on the audited PC. No third-party code is bundled,
# distributed or modified. Product names and trademarks belong to their respective owners; no affiliation or endorsement is implied.
$script:Sig = @{
    RemoteA = @{ Folder = 'AnyDesk';   ConfFile = 'system.conf'; ExeName = 'AnyDesk.exe';   ProcPat = '^AnyDesk';   CliArgs = '--get-id'
                 IdRx = '(?m)^\s*ad\.(?:anynet|anydesk)\.id\s*=\s*(\d+)' }
    RemoteB = @{ Folder = 'HopToDesk'; ConfFile = 'HopToDesk.toml'; ExeName = 'HopToDesk.exe'; ProcPat = '^HopToDesk'; CliArgs = '--get-id'
                 IdRx = '(?m)^\s*id\s*=\s*[''"]([A-Za-z0-9]+)[''"]' }
    DiskExclude = 'MiniTool|ShadowMaker|ShadowCopy|Volume Shadow|SDRSVC|SDXHelper'
    Disk = [ordered]@{
        'Disk protection (type A)' = @{ Pat = 'Deep ?Freeze|DFServ|DF5Serv|DepFrz|DeepFrz|FrzState2k|DFRTSvc|Persi0'
                                        Paths = @('C:\Persi0', 'C:\Program Files\Faronics\Deep Freeze*', 'C:\Program Files (x86)\Faronics\Deep Freeze*',
                                                  (Join-Path $env:windir 'SysWOW64\DFServ.exe'), (Join-Path $env:windir 'System32\DFServ.exe'),
                                                  (Join-Path $env:windir 'System32\drivers\DepFrz.sys')) }
        'Disk protection (type B)' = @{ Pat = 'Shadow ?Defender|ShadowDefender|SDCoreService|SDDrv'
                                        Paths = @('C:\Program Files\Shadow Defender', 'C:\Program Files (x86)\Shadow Defender') }
    }
}

# ---- is the program present at all? (tells "not installed" from "installed, but its ID was not found") ----
function Test-AppPresent([string]$pat) {
    $why = @()
    try { $x = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $pat } | Select-Object -First 1; if ($x) { $why += "process: $($x.Name)" } } catch { }
    try { $x = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match $pat } | Select-Object -First 1; if ($x) { $why += "service: $($x.PSChildName)" } } catch { }
    try { $x = Get-Uninstall | Where-Object { $_.DisplayName -match $pat } | Select-Object -First 1; if ($x) { $why += "installed: $($x.DisplayName)" } } catch { }
    $why
}

# executables of a program: Seen = anywhere (running copy, portable), Installed = Program Files / uninstall entry / config.json (safe to call with a CLI switch)
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

# ---- remote access tool A: plain-text ID setting in the program's config folder; portable copies keep it in %APPDATA% too ----
function Get-RemoteIdA {
    $A = $script:Sig.RemoteA
    $files = @()
    if ($env:ProgramData) { $files += Join-Path $env:ProgramData ($A.Folder + '\' + $A.ConfFile) }
    if ($env:APPDATA)     { $files += Join-Path $env:APPDATA ($A.Folder + '\' + $A.ConfFile) }
    foreach ($d in (Get-UserProfileDirs)) { $files += Join-Path $d ('AppData\Roaming\' + $A.Folder + '\' + $A.ConfFile) }
    foreach ($d in @(Cfg 'remoteAccessDetect.extraConfigDirsA' @())) { if ($d) { $files += Join-Path ([string]$d) $A.ConfFile } }     # config.json: non-standard config folders
    foreach ($f in ($files | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $f)) { Write-Log DEBUG "remote A: no file $f"; continue }
        try {
            $m = [regex]::Match((Read-TextSmart $f), $A.IdRx)
            if ($m.Success) { $script:Src.RemoteA = $f; Write-Log DEBUG "remote A: id found in $f"; return $m.Groups[1].Value }
            Write-Log DEBUG "remote A: $f exists, but has no ID line"
        } catch { Write-Log DEBUG "remote A: cannot read ${f}: $($_.Exception.Message)" }
    }
    # no config: ask an INSTALLED copy through its command-line switch (can be turned off: features.remoteAccessCli / -NoRemoteCli)
    if (-not $NoRemoteCli) {
        $ex = Get-AppExePaths $A.Folder $A.ProcPat @(Get-ProgramFilesPaths ($A.Folder + '\' + $A.ExeName)) $A.ExeName 'remoteAccessDetect.extraPathsA'
        foreach ($exe in @($ex.Installed | Select-Object -First 2)) {
            $x = Invoke-External $exe $A.CliArgs ([int](Cfg 'timeouts.remoteCliSec' 8))
            Write-Log DEBUG "remote A: cli $exe $($A.CliArgs) exit=$($x.ExitCode) timeout=$($x.TimedOut) error=$($x.Error)"
            $m = [regex]::Match($x.Stdout, '(?m)^\s*(\d{6,})\s*$')
            if ($m.Success) { $script:Src.RemoteA = "$exe $($A.CliArgs) (CLI)"; return $m.Groups[1].Value }
        }
    }
    $why = @(Test-AppPresent $A.ProcPat)
    try {   # portable copy lying around (desktop / downloads), not running
        foreach ($d in (Get-UserProfileDirs)) { foreach ($sub in 'Desktop', 'Downloads') {
            $x = Get-ChildItem (Join-Path $d $sub) -Filter ($A.Folder + '*.exe') -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($x) { $why += "portable exe: $($x.FullName)" }
        } }
    } catch { }
    if ($why.Count) {
        $script:Src.RemoteA = 'present, but no ID found: ' + ($why -join ' ; ')
        Write-Log WARN 'Remote access tool A is present, but its ID was not found (start it once, or add its config folder to config.json: remoteAccessDetect.extraConfigDirsA)'
        return $NoId
    }
    Write-Log DEBUG 'remote A: not installed, ID not found in any known location'
    return $NO
}

# ---- remote access tool B: ID in a *.toml settings file (or through the installed program's CLI) ----
function Find-RemoteIdB($dir) {
    $B = $script:Sig.RemoteB
    $tomls = @(Get-ChildItem $dir -Recurse -Depth 3 -Filter '*.toml' -File -Force -ErrorAction SilentlyContinue |
               Sort-Object @{ e = { if ($_.Name -ieq $B.ConfFile) { 0 } else { 1 } } }, Name)
    foreach ($f in $tomls) {
        try {
            $m = [regex]::Match((Read-TextSmart $f.FullName), $B.IdRx)
            if ($m.Success) { return [pscustomobject]@{ Id = $m.Groups[1].Value; File = $f.FullName } }
        } catch { Write-Log DEBUG "remote B: cannot read $($f.FullName): $($_.Exception.Message)" }
    }
    $null
}

function Get-RemoteIdB {
    $B = $script:Sig.RemoteB
    $log = New-Object Collections.ArrayList
    $note = { param($m) [void]$log.Add($m); Write-Log DEBUG "remote B: $m" }
    $dirs = @()
    if (-not $NoRemoteCli) {   # some builds keep no plain ID in *.toml: ask the installed program itself
        $ex = Get-AppExePaths $B.Folder $B.ProcPat @(Get-ProgramFilesPaths ($B.Folder + '\' + $B.ExeName)) $B.ExeName 'remoteAccessDetect.extraPathsB'
        if ($ex.Installed.Count) {
            $to = [int](Cfg 'timeouts.remoteCliSec' 8)
            foreach ($exe in @($ex.Installed | Select-Object -First 2)) {
                $x = Invoke-External $exe $B.CliArgs $to
                & $note "cli $exe $($B.CliArgs) exit=$($x.ExitCode) timeout=$($x.TimedOut) error=$($x.Error)"
                $m = [regex]::Match($x.Stdout, '(?m)^\s*(\d{6,})\s*$')
                if ($m.Success) { $script:Src.RemoteB = "$exe $($B.CliArgs) (CLI)"; return $m.Groups[1].Value }
                & $note 'cli returned no numeric ID'
            }
        } else { & $note 'executable not found (Program Files, per-user install, uninstall entries, config.json)' }
    }

    if ($env:APPDATA)     { $dirs += Join-Path $env:APPDATA $B.Folder }
    if ($env:ProgramData) { $dirs += Join-Path $env:ProgramData $B.Folder }
    foreach ($d in (Get-UserProfileDirs)) { $dirs += Join-Path $d ('AppData\Roaming\' + $B.Folder); $dirs += Join-Path $d ('AppData\Local\' + $B.Folder) }
    foreach ($d in ($dirs | Select-Object -Unique)) {
        $ex2 = Test-Path $d; & $note "dir $d exists=$ex2"
        if (-not $ex2) { continue }
        $r = Find-RemoteIdB $d
        if ($r) { $script:Src.RemoteB = $r.File; return $r.Id }
        & $note '   no id in *.toml'
    }

    # service profiles are ACL-protected: copy *.toml with backup privilege (robocopy /B), then parse the copy.
    # /B needs an elevated session, without it robocopy only fails, so it is skipped.
    if (Test-IsAdmin) {
        $tmpRoot = Join-Path $env:TEMP ('ra_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $rto = [int](Cfg 'timeouts.robocopySec' 30)
        try {
            foreach ($s in 'C:\Windows\ServiceProfiles\LocalService', 'C:\Windows\ServiceProfiles\NetworkService', 'C:\Windows\System32\config\systemprofile') {
                $src = Join-Path $s ('AppData\Roaming\' + $B.Folder)
                $dst = Join-Path $tmpRoot (Split-Path $s -Leaf)
                try {
                    $x = Invoke-External 'robocopy' ('"{0}" "{1}" *.toml /E /B /R:0 /W:0 /NP /NJH /NJS /NFL /NDL' -f $src, $dst) $rto
                    & $note "robocopy /B $src exit=$($x.ExitCode) timeout=$($x.TimedOut) $($x.Error)"
                    if (Test-Path $dst) {
                        $r = Find-RemoteIdB $dst
                        if ($r) { $script:Src.RemoteB = $r.File.Replace($dst, $src) + ' (backup-mode copy)'; return $r.Id }
                        & $note '   copied, but no id in *.toml'
                    }
                } catch { & $note "robocopy error: $($_.Exception.Message)" }
            }
        } finally { Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue }
    } else { & $note 'not elevated: service profiles (robocopy /B) skipped' }

    $why = @(Test-AppPresent $B.ProcPat)
    if ($why.Count) {
        $script:Src.RemoteB = 'present, but no ID found: ' + ($why -join ' ; ')
        Write-Host '  Remote access tool B is present, but its ID was not found; search log: Service\remote_search.txt' -ForegroundColor Yellow
        foreach ($w in $why) { [void]$log.Add($w) }
        try { $log | Out-File (Join-Path $SvcDir 'remote_search.txt') -Encoding utf8 } catch { }
        return $NoId
    }
    return $NO
}

# ---- disk protection software: services, processes, drivers (all in the Services registry key), uninstall entries, known folders ----
# Presence is detected; the protected / unprotected state cannot be read reliably, so it is not claimed.
function Get-DiskProtectionStatus {
    $on   = [string](Cfg 'diskProtectionDetect.enabledText' (U '\u0412\u043a\u043b\u044e\u0447\u0435\u043d\u043e'))
    $excl = [string]$script:Sig.DiskExclude     # look-alikes that are NOT disk protection
    $defs = [ordered]@{}
    foreach ($k in $script:Sig.Disk.Keys) { $defs[$k] = $script:Sig.Disk[$k] }
    foreach ($d in @(Cfg 'diskProtectionDetect.disableBuiltin' @())) { $defs.Remove([string]$d) }       # config.json: drop a built-in entry
    foreach ($xp in @(Cfg 'diskProtectionDetect.extraProducts' @())) {                                  # config.json: add your own entry
        if ($xp.name -and $xp.pattern) { $defs[[string]$xp.name] = @{ Pat = [string]$xp.pattern; Paths = @($xp.paths | Where-Object { $_ }) } }
    }
    $ex2 = [string](Cfg 'diskProtectionDetect.excludePattern' ''); if ($ex2) { $excl = "$excl|$ex2" }
    $procs = @(); try { $procs = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) } catch { Write-Log DEBUG "disk protection: Get-Process failed: $($_.Exception.Message)" }
    $svcs  = @(); try { $svcs = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction SilentlyContinue | ForEach-Object { "$($_.PSChildName) | $($_.GetValue('DisplayName')) | $($_.GetValue('ImagePath'))" }) } catch { Write-Log DEBUG "disk protection: cannot read the Services registry key: $($_.Exception.Message)" }
    $apps  = @(Get-Uninstall | ForEach-Object { "$($_.DisplayName) | $($_.Publisher)" })

    $res = @(); $why = @()
    try {                                               # native: Windows Unified Write Filter (Enterprise / Education / IoT editions)
        $f = Get-CimInstance -Namespace 'root\standardcimv2\embedded' -ClassName UWF_Filter -ErrorAction Stop | Select-Object -First 1
        if ($f -and $f.CurrentEnabled) { $res += "Windows UWF $([char]0x2014) $on"; $why += 'UWF_Filter.CurrentEnabled = True' }
    } catch { Write-Log DEBUG "disk protection: UWF is not available: $($_.Exception.Message)" }
    foreach ($prod in $defs.Keys) {
        $pat = $defs[$prod].Pat; $ev = @()
        $x = $procs | Where-Object { $_ -match $pat -and $_ -notmatch $excl } | Select-Object -First 1; if ($x) { $ev += "process: $x" }
        $x = $svcs  | Where-Object { $_ -match $pat -and $_ -notmatch $excl } | Select-Object -First 1; if ($x) { $ev += "service/driver: $x" }
        $x = $apps  | Where-Object { $_ -match $pat -and $_ -notmatch $excl } | Select-Object -First 1; if ($x) { $ev += "installed: $x" }
        foreach ($p in $defs[$prod].Paths) { if (Test-Path $p -ErrorAction SilentlyContinue) { $ev += "path: $p"; break } }
        if (-not $ev.Count) { Write-Log DEBUG "disk protection: $prod - no evidence (processes=$($procs.Count) services=$($svcs.Count) apps=$($apps.Count))"; continue }
        $res += "$prod $([char]0x2014) $on"
        $why += "$prod <- " + ($ev -join ' ; ')
        Write-Log DEBUG ("disk protection: $prod - " + ($ev -join ' ; '))
    }
    if ($res.Count) { $script:Src.Disk = ($why -join ' || '); return ($res -join '; ') }
    return $NO
}

# ---- PC identity (serial number, model): BIOS / board / product CIM classes; placeholder values of cheap boards are ignored ----
function Get-PcIdentity {
    if ($script:Identity) { return $script:Identity }
    $junk = '^(To be filled.*|Default string|System Serial Number|System Product Name|System manufacturer|Not Specified|Not Applicable|None|N/A|Unknown|0+|O\.?E\.?M\.?.*|Chassis Serial Number|Serial Number|Type1ProductConfigId|123456789.*|0123456789.*|x\.x|\s*)$'
    $serial = ''
    foreach ($src in @(@('Win32_BIOS', 'SerialNumber'), @('Win32_ComputerSystemProduct', 'IdentifyingNumber'), @('Win32_BaseBoard', 'SerialNumber'))) {
        try {
            $v = [string]((Get-CimSafe $src[0] | Select-Object -First 1).($src[1])); $v = $v.Trim()
            if ($v -and $v -notmatch $junk) { $serial = $v; break }
        } catch { Write-Log DEBUG "identity: $($src[0]) failed: $($_.Exception.Message)" }
    }
    $model = ''
    try {
        $cs = Get-CimSafe Win32_ComputerSystem | Select-Object -First 1
        $mf = ([string]$cs.Manufacturer).Trim(); $md = ([string]$cs.Model).Trim()
        if ($mf -match $junk) { $mf = '' }
        if ($md -match $junk) { $md = ''; try { $bp = ([string](Get-CimSafe Win32_BaseBoard | Select-Object -First 1).Product).Trim(); if ($bp -notmatch $junk) { $md = $bp } } catch { } }
        $model = if ($mf -and $md -and $md -notlike "$mf*") { "$mf $md" } else { "$mf$md".Trim() }
    } catch { Write-Log DEBUG "identity: model failed: $($_.Exception.Message)" }
    $script:Identity = [pscustomobject]@{ Serial = $serial; Model = $model }
    $script:Identity
}

# ---- open a file in Google Chrome (config.json: ui.browser = "chrome" | "default"); falls back to the default program ----
function Get-ChromePath {
    $c = @()
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe') {
        try { $v = (Get-ItemProperty -LiteralPath $k -ErrorAction Stop).'(default)'; if ($v) { $c += [string]$v } } catch { }
    }
    foreach ($b in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) { if ($b) { $c += (Join-Path $b 'Google\Chrome\Application\chrome.exe') } }
    foreach ($x in $c) { if ($x -and (Test-Path -LiteralPath $x -PathType Leaf)) { return $x } }
    $null
}
function Open-InBrowser([string]$path) {
    if ([string](Cfg 'ui.browser' 'chrome') -ieq 'chrome') {
        $chrome = Get-ChromePath
        if ($chrome) {
            try { Start-Process -FilePath $chrome -ArgumentList ('"' + $path + '"'); return } catch { Write-Log WARN "Chrome could not be started: $($_.Exception.Message)" }
        } else { Write-Log WARN 'Google Chrome was not found: the report is opened in the default browser' }
    }
    Start-Process $path
}

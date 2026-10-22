# ===================== INVENTORY: data collectors =====================
function Tm($name, [scriptblock]$b) {
    $sw = [Diagnostics.Stopwatch]::StartNew(); $r = & $b
    Write-Host ('  ({0}: {1:N1}s)' -f $name, $sw.Elapsed.TotalSeconds) -ForegroundColor DarkGray
    $r
}

function Get-UserProfileDirs {
    $r = @()
    try { $r += (Get-ChildItem 'C:\Users' -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) } catch { }
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

# ---- AnyDesk: ID is "ad.anynet.id=NNN" in system.conf (older builds: ad.anydesk.id) ----
function Get-AnyDeskId {
    $files = @()
    if ($env:ProgramData) { $files += Join-Path $env:ProgramData 'AnyDesk\system.conf' }
    if ($env:APPDATA)     { $files += Join-Path $env:APPDATA 'AnyDesk\system.conf' }
    foreach ($d in (Get-UserProfileDirs)) { $files += Join-Path $d 'AppData\Roaming\AnyDesk\system.conf' }
    foreach ($f in ($files | Select-Object -Unique)) {
        if (-not (Test-Path $f)) { continue }
        try {
            $m = [regex]::Match((Read-TextSmart $f), '(?m)^\s*ad\.(?:anynet|anydesk)\.id\s*=\s*(\d+)')
            if ($m.Success) { $script:Src.AnyDesk = $f; return $m.Groups[1].Value }
        } catch { }
    }
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
        } catch { }
    }
    $null
}

function Get-HopToDeskId {
    $log = @(); $dirs = @()
    if (-not $NoHopCli) {   # HopToDesk 1.46.x keeps no plain ID in *.toml: ask the app itself (HopToDesk.exe --get-id)
        $exe = @('C:\Program Files (x86)\HopToDesk\HopToDesk.exe', 'C:\Program Files\HopToDesk\HopToDesk.exe') | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($exe) {
            try {
                $of = Join-Path $env:TEMP 'h2d_id.txt'; Remove-Item $of -ErrorAction SilentlyContinue
                $p = Start-Process $exe -ArgumentList '--get-id' -RedirectStandardOutput $of -WindowStyle Hidden -PassThru
                if (-not $p.WaitForExit(5000)) { $p.Kill() }
                $m = [regex]::Match((Get-Content $of -Raw), '(?m)^\s*(\d{6,})\s*$')
                if ($m.Success) { $script:Src.Hop = "$exe --get-id (CLI)"; return $m.Groups[1].Value }
            } catch { $log += "cli error: $($_.Exception.Message)" }
        }
    }

    if ($env:APPDATA)     { $dirs += Join-Path $env:APPDATA 'HopToDesk' }
    if ($env:ProgramData) { $dirs += Join-Path $env:ProgramData 'HopToDesk' }
    foreach ($d in (Get-UserProfileDirs)) { $dirs += Join-Path $d 'AppData\Roaming\HopToDesk'; $dirs += Join-Path $d 'AppData\Local\HopToDesk' }
    foreach ($d in ($dirs | Select-Object -Unique)) {
        $ex = Test-Path $d; $log += "dir $d exists=$ex"
        if (-not $ex) { continue }
        $r = Find-HopId $d
        if ($r) { $script:Src.Hop = $r.File; return $r.Id }
        $log += '   no id in *.toml'
    }
    # service profiles are ACL-protected: copy *.toml with backup privilege (robocopy /B), then parse the copy
    $tmpRoot = Join-Path $env:TEMP ('h2d_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        foreach ($s in 'C:\Windows\ServiceProfiles\LocalService', 'C:\Windows\ServiceProfiles\NetworkService', 'C:\Windows\System32\config\systemprofile') {
            $src = Join-Path $s 'AppData\Roaming\HopToDesk'
            $dst = Join-Path $tmpRoot (Split-Path $s -Leaf)
            try {
                $p = Start-Process robocopy -ArgumentList ('"{0}" "{1}" *.toml /E /B /R:0 /W:0 /NP /NJH /NJS /NFL /NDL' -f $src, $dst) -Wait -PassThru -WindowStyle Hidden
                $log += "robocopy /B $src exit=$($p.ExitCode)"
                if (Test-Path $dst) {
                    $r = Find-HopId $dst
                    if ($r) { $script:Src.Hop = $r.File.Replace($dst, $src) + ' (backup-mode copy)'; return $r.Id }
                    $log += '   copied, but no id in *.toml'
                }
            } catch { $log += "robocopy error: $($_.Exception.Message)" }
        }
    } finally { Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue }

    $running = @(Get-Process -Name 'HopToDesk*' -ErrorAction SilentlyContinue)
    if (@(Get-Uninstall | Where-Object { $_.DisplayName -match 'HopToDesk' }).Count -or $running.Count) {
        Write-Host '  HopToDesk is installed but its ID file was not found; search log: Raports\_hop_search.txt' -ForegroundColor Yellow
        try { $running | ForEach-Object { $log += "process $($_.Name) $($_.Path)" } } catch { }
        try { $log | Out-File (Join-Path $OutDir '_hop_search.txt') -Encoding utf8 } catch { }
    }
    return $NO
}

# ---- Deep Freeze / Shadow Defender: services, processes, drivers, uninstall entries, known folders ----
function Get-FreezeStatus {
    $on   = [string](Cfg 'freeze.enabledText' (U '\u0412\u043a\u043b\u044e\u0447\u0435\u043d\u043e'))
    $excl = 'MiniTool|ShadowMaker|ShadowCopy|Volume Shadow|SDRSVC|SDXHelper'     # look-alikes that are NOT freeze software
    $defs = [ordered]@{
        'Deep Freeze'     = @{ Pat = 'Faronics|Deep ?Freeze|DFServ|DF5Serv|DepFrz|DeepFrz|FrzState2k|DFRTSvc|Persi0'
                               Paths = @('C:\Persi0', 'C:\Program Files\Faronics', 'C:\Program Files (x86)\Faronics',
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
    $procs = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    $svcs  = @(); try { $svcs = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction SilentlyContinue | ForEach-Object { "$($_.PSChildName) | $($_.GetValue('DisplayName')) | $($_.GetValue('ImagePath'))" }) } catch { }   # services + drivers straight from the registry (fast)
    $drvs  = @()
    $apps  = @(Get-Uninstall | ForEach-Object { "$($_.DisplayName) | $($_.Publisher)" })

    $res = @(); $why = @()
    foreach ($prod in $defs.Keys) {
        $pat = $defs[$prod].Pat; $ev = @()
        $x = $procs | Where-Object { $_ -match $pat -and $_ -notmatch $excl } | Select-Object -First 1; if ($x) { $ev += "process: $x" }
        $x = $svcs  | Where-Object { $_ -match $pat -and $_ -notmatch $excl } | Select-Object -First 1; if ($x) { $ev += "service: $x" }
        $x = $drvs  | Where-Object { $_ -match $pat -and $_ -notmatch $excl } | Select-Object -First 1; if ($x) { $ev += "driver: $x" }
        $x = $apps  | Where-Object { $_ -match $pat -and $_ -notmatch $excl } | Select-Object -First 1; if ($x) { $ev += "installed: $x" }
        foreach ($p in $defs[$prod].Paths) { if (Test-Path $p -ErrorAction SilentlyContinue) { $ev += "path: $p"; break } }
        if (-not $ev.Count) { continue }
        $name = $prod
        if ($prod -eq 'Deep Freeze') {
            $ed = [regex]::Match(($apps -join "`n"), 'Deep Freeze\s+(Standard|Enterprise|Server)')
            $name = if ($ed.Success) { $ed.Value -replace '\s+', ' ' } else { 'Deep Freeze Standard' }
        }
        $res += "$name $([char]0x2014) $on"
        $why += "$prod <- " + ($ev -join ' ; ')
    }
    if ($res.Count) { $script:Src.Freeze = ($why -join ' || '); return ($res -join '; ') }
    return $NO
}


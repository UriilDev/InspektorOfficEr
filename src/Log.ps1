# ===================== LOG, DIAGNOSTICS, EXTERNAL PROCESSES =====================
$script:LogLevels = @{ DEBUG = 0; INFO = 1; WARN = 2; ERROR = 3 }
$script:LogBuf    = New-Object System.Collections.Generic.List[string]

# Write-Log <DEBUG|INFO|WARN|ERROR> <message>
# Every message is kept in memory (it goes to the -Diagnose file); the console shows messages at or above
# config.json log.level (default INFO). With -Diagnose the console shows everything.
function Write-Log([string]$Level, [string]$Message) {
    $lv = $Level.ToUpper()
    if (-not $script:LogLevels.ContainsKey($lv)) { $lv = 'INFO' }
    if ($script:LogBuf.Count -lt 5000) { [void]$script:LogBuf.Add(('{0} [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss.fff'), $lv, $Message)) }
    $min = $script:LogLevels[([string](Cfg 'log.level' 'INFO')).ToUpper()]
    if ($null -eq $min) { $min = 1 }
    if ($Diagnose) { $min = 0 }
    if ($script:LogLevels[$lv] -lt $min) { return }
    $color = 'Gray'
    if ($lv -eq 'ERROR') { $color = 'Red' } elseif ($lv -eq 'WARN') { $color = 'Yellow' } elseif ($lv -eq 'DEBUG') { $color = 'DarkGray' }
    Write-Host ('  [{0}] {1}' -f $lv, $Message) -ForegroundColor $color
}

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

# CIM query that never throws: a broken WMI class must not kill the whole report (returns an empty array)
function Get-CimSafe {
    try { Get-CimInstance @args }
    catch { Write-Log WARN ('CIM query failed ({0}): {1}' -f (($args | Where-Object { $_ -is [string] -and $_ -notlike '-*' } | Select-Object -First 1)), $_.Exception.Message); @() }
}

# Runs an external program with a hard timeout. Never throws.
# Returns: ExitCode (null on timeout), Stdout, Stderr, TimedOut, Error
function Invoke-External([string]$FilePath, [string]$Arguments = '', [int]$TimeoutSec = 10) {
    $r = [pscustomobject]@{ ExitCode = $null; Stdout = ''; Stderr = ''; TimedOut = $false; Error = '' }
    $p = $null
    try {
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $FilePath; $psi.Arguments = $Arguments
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $p = [Diagnostics.Process]::Start($psi)
        # poll both pipes and keep whatever arrived: a child left behind may hold the pipes open after the program exited
        $bo = New-Object char[] 4096; $be = New-Object char[] 4096
        $so = New-Object Text.StringBuilder; $se = New-Object Text.StringBuilder
        $to = $p.StandardOutput.ReadAsync($bo, 0, $bo.Length); $te = $p.StandardError.ReadAsync($be, 0, $be.Length)
        $doneO = $false; $doneE = $false; $exitedAt = $null
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($true) {
            if (-not $doneO -and $to.IsCompleted) {
                $n = 0; if (-not $to.IsFaulted) { $n = $to.Result }
                if ($n -gt 0) { [void]$so.Append($bo, 0, $n); $to = $p.StandardOutput.ReadAsync($bo, 0, $bo.Length) } else { $doneO = $true }
            }
            if (-not $doneE -and $te.IsCompleted) {
                $n = 0; if (-not $te.IsFaulted) { $n = $te.Result }
                if ($n -gt 0) { [void]$se.Append($be, 0, $n); $te = $p.StandardError.ReadAsync($be, 0, $be.Length) } else { $doneE = $true }
            }
            if ($p.HasExited -and $null -eq $exitedAt) { $exitedAt = $sw.ElapsedMilliseconds }
            if ($p.HasExited -and $doneO -and $doneE) { break }
            if ($null -ne $exitedAt -and ($sw.ElapsedMilliseconds - $exitedAt) -gt 1000) { break }
            if ($sw.ElapsedMilliseconds -gt ($TimeoutSec * 1000)) {
                $r.TimedOut = $true
                try { $p.Kill() } catch { }
                [void]$p.WaitForExit(2000)
                break
            }
            Start-Sleep -Milliseconds 20
        }
        $r.Stdout = $so.ToString(); $r.Stderr = $se.ToString()
        if (-not $r.TimedOut) { $r.ExitCode = $p.ExitCode }
    } catch { $r.Error = $_.Exception.Message }
    finally { if ($p) { try { $p.Dispose() } catch { } } }
    Write-Log DEBUG ("exec: {0} {1} -> exit={2} timeout={3} error='{4}' stdout={5}b" -f $FilePath, $Arguments, $r.ExitCode, $r.TimedOut, $r.Error, $r.Stdout.Length)
    $r
}

# ---- -Diagnose: environment summary (no user names, no file contents) ----
function Get-EnvironmentInfo {
    $l = @()
    $l += "app            : $AppName $AppVer"
    $l += "powershell     : $($PSVersionTable.PSVersion) (CLR $($PSVersionTable.CLRVersion))"
    $os = @(Get-CimSafe Win32_OperatingSystem | Select-Object -First 1)
    if ($os.Count -and $os[0]) { $l += "os             : $($os[0].Caption) $($os[0].Version) $($os[0].OSArchitecture)" }
    else { $l += "os             : $([Environment]::OSVersion.VersionString) (WMI unavailable)" }
    $v = [Environment]::OSVersion.Version
    $l += "windows 7/2008  : $(($v.Major -eq 6 -and $v.Minor -le 1))"
    $l += "elevated (admin): $(Test-IsAdmin)"
    try { $l += "exec policy    : $(Get-ExecutionPolicy)" } catch { }
    $dt = 'unknown'
    try {
        if ($Drive) {
            $ld = @(Get-CimSafe Win32_LogicalDisk -Filter ("DeviceID='" + $Drive + "'") | Select-Object -First 1)
            if ($ld.Count -and $ld[0]) { $dt = @{ 2 = 'removable'; 3 = 'fixed'; 4 = 'network'; 5 = 'optical' }[[int]$ld[0].DriveType] }
        }
    } catch { }
    $l += "script drive    : $Drive ($dt)"
    $l += "config.json     : $(if ($script:Cfg) { 'loaded' } else { 'not found / invalid (defaults)' })"
    $l += "switches        : SkipReport=$SkipReport SkipExcel=$SkipExcel NoHopCli=$NoHopCli NoPrompt=$NoPrompt Diagnose=$Diagnose"
    $l += "features        : report=$(Cfg 'features.report' $true) excel=$(Cfg 'features.excel' $true) anyDesk=$(Cfg 'features.anyDesk' $true) hopToDesk=$(Cfg 'features.hopToDesk' $true) freezeDetect=$(Cfg 'features.freezeDetect' $true)"
    $l += "timeouts (sec)  : hopCli=$(Cfg 'timeouts.hopToDeskCliSec' 8) robocopy=$(Cfg 'timeouts.robocopySec' 30)"
    $l
}

function Save-DiagnoseLog([string]$dir) {
    $d = Join-Path $dir '_debug'
    New-Item -ItemType Directory -Force $d | Out-Null
    $pc = $env:COMPUTERNAME; if (-not $pc) { $pc = [Environment]::MachineName }
    $f = Join-Path $d ('diagnose_{0}_{1}.txt' -f $pc, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $lines = @('InspektorOfficEr diagnostic log (safe to share: contains the PC name, no user data)', '') + @(Get-EnvironmentInfo) + @('', '--- log ---') + @($script:LogBuf)
    [IO.File]::WriteAllLines($f, [string[]]$lines, (New-Object Text.UTF8Encoding($true)))
    $f
}

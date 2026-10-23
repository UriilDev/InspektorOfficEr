# ===================== QUICK CHECKS: thresholds from config.json (section "checks"), plain wording =====================
function New-Check([string]$Level, [string]$Text, [string]$Action = '', [string]$Short = '') { [pscustomobject]@{ L = $Level; T = $Text; A = $Action; S = $Short } }

function ConvertTo-Date([string]$s) {
    try { [datetime]::ParseExact($s, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) } catch { $null }
}

# End of support by Windows build (Microsoft lifecycle pages). Home/Pro and Enterprise/Education differ for Windows 11.
# Fix or extend in config.json: "checks": { "osSupport": [ { "build": "26200", "home": "2027-10-12", "ent": "2028-10-10" } ] }
# Returns a date, $null when unknown (then no claim is made). A date before 2010 means "ended long ago".
function Get-OsSupportEnd($os) {
    $cap = [string]$os.Caption; $b = 0
    [void][int]::TryParse([string]$os.BuildNumber, [ref]$b)
    if ($b -le 0 -or $cap -notmatch 'Windows (10|11)') { return $null }
    $isEnt = ($cap -match 'Enterprise|Education|IoT')
    foreach ($e in @(Cfg 'checks.osSupport' @())) {
        if ([string]$e.build -eq [string]$b) {
            $s = $(if ($isEnt -and $e.ent) { [string]$e.ent } else { [string]$e.home })
            $d = ConvertTo-Date $s; if ($d) { return $d }
        }
    }
    if ($b -lt 22000) {                      # Windows 10
        if ($cap -match 'LTSC|LTSB') {
            $lt = @{ 14393 = '2026-10-13'; 17763 = '2029-01-09'; 19044 = '2027-01-12' }
            $s = $lt[$b]
            if ($b -eq 19044 -and $cap -match 'IoT') { $s = '2032-01-13' }
        }
        elseif ($b -ge 19045) { $s = '2025-10-14' }
        else { $s = '2000-01-01' }
        if (-not $s) { return $null }
        return (ConvertTo-Date $s)
    }
    $w11 = @{ 22000 = @('2023-10-10', '2024-10-08'); 22621 = @('2024-10-08', '2025-10-14'); 22631 = @('2025-11-11', '2026-11-10'); 26100 = @('2026-10-13', '2027-10-12') }
    $p = $w11[$b]
    if (-not $p) { return $null }
    $s = $(if ($isEnt) { $p[1] } else { $p[0] })
    ConvertTo-Date $s
}

function Get-OsSupportCheck($os) {
    $cap = ([string]$os.Caption).Trim()
    if (-not $cap) { return $null }
    if ($cap -match 'Windows (7|8|Vista|XP)|2003|2008|Server 2012') {
        return (New-Check 'bad' ((U '\u0423\u0441\u0442\u0430\u0440\u0435\u0432\u0448\u0430\u044f \u041e\u0421 \u0431\u0435\u0437 \u043f\u043e\u0434\u0434\u0435\u0440\u0436\u043a\u0438: ') + $cap) (U '\u041e\u0431\u043d\u043e\u0432\u0438\u0442\u044c \u0438\u043b\u0438 \u0437\u0430\u043c\u0435\u043d\u0438\u0442\u044c \u041e\u0421 (\u0431\u0435\u0437 \u043e\u0431\u043d\u043e\u0432\u043b\u0435\u043d\u0438\u0439 \u0431\u0435\u0437\u043e\u043f\u0430\u0441\u043d\u043e\u0441\u0442\u0438 \u043f\u043e\u0432\u044b\u0448\u0435\u043d \u0440\u0438\u0441\u043a \u0432\u0437\u043b\u043e\u043c\u0430)') (U '\u041e\u0421 \u0431\u0435\u0437 \u043f\u043e\u0434\u0434\u0435\u0440\u0436\u043a\u0438'))
    }
    $end = Get-OsSupportEnd $os
    if (-not $end) { return (New-Check 'ok' ((U '\u041e\u0421: ') + $cap)) }
    $warnDays = [int](Cfg 'checks.osSupportWarnDays' 90)
    $days = [int][math]::Floor(($end - (Get-Date).Date).TotalDays)
    $act = U '\u041e\u0431\u043d\u043e\u0432\u0438\u0442\u044c Windows \u0434\u043e \u043f\u043e\u0434\u0434\u0435\u0440\u0436\u0438\u0432\u0430\u0435\u043c\u043e\u0439 \u0432\u0435\u0440\u0441\u0438\u0438 (\u0435\u0441\u043b\u0438 \u043e\u0444\u043e\u0440\u043c\u043b\u0435\u043d\u0430 \u043f\u043b\u0430\u0442\u043d\u0430\u044f \u043f\u0440\u043e\u0434\u043b\u0451\u043d\u043d\u0430\u044f \u043f\u043e\u0434\u0434\u0435\u0440\u0436\u043a\u0430 - \u044d\u0442\u043e \u043c\u043e\u0436\u043d\u043e \u0438\u0433\u043d\u043e\u0440\u0438\u0440\u043e\u0432\u0430\u0442\u044c)'
    if ($days -lt 0) {
        $when = $(if ($end.Year -ge 2010) { ' ' + $end.ToString('dd.MM.yyyy') } else { '' })
        return (New-Check 'bad' (((U '\u041f\u043e\u0434\u0434\u0435\u0440\u0436\u043a\u0430 \u044d\u0442\u043e\u0439 \u0432\u0435\u0440\u0441\u0438\u0438 Windows \u0437\u0430\u043a\u043e\u043d\u0447\u0438\u043b\u0430\u0441\u044c') + $when + ': ') + $cap) $act (U '\u041e\u0421 \u0431\u0435\u0437 \u043f\u043e\u0434\u0434\u0435\u0440\u0436\u043a\u0438'))
    }
    if ($days -le $warnDays) {
        return (New-Check 'warn' (((U '\u041f\u043e\u0434\u0434\u0435\u0440\u0436\u043a\u0430 \u044d\u0442\u043e\u0439 \u0432\u0435\u0440\u0441\u0438\u0438 Windows \u0437\u0430\u043a\u043e\u043d\u0447\u0438\u0442\u0441\u044f ') + $end.ToString('dd.MM.yyyy') + (U ' (\u0447\u0435\u0440\u0435\u0437 ') + $days + (U ' \u0434\u043d.): ')) + $cap) $act (U '\u0421\u043a\u043e\u0440\u043e \u043a\u043e\u043d\u0435\u0446 \u043f\u043e\u0434\u0434\u0435\u0440\u0436\u043a\u0438 \u041e\u0421'))
    }
    New-Check 'ok' ((U '\u041e\u0421 \u043f\u043e\u0434\u0434\u0435\u0440\u0436\u0438\u0432\u0430\u0435\u0442\u0441\u044f \u0434\u043e ') + $end.ToString('dd.MM.yyyy') + ': ' + $cap)
}

# SecurityCenter2 productState: 3 bytes as hex. Middle byte high nibble 1 = protection on, last byte not 00 = signatures out of date.
# (decoding is the widely used one, requires a test on real Windows 7/10/11 PCs)
function Get-AvCheck {
    $items = @()
    try { $items = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop) }
    catch { Write-Log DEBUG "report: SecurityCenter2 unavailable: $($_.Exception.Message)" }
    $list = @()
    foreach ($p in $items) {
        $name = ([string]$p.displayName).Trim(); if (-not $name) { continue }
        $st = [int64]0; try { $st = [int64]$p.productState } catch { }
        $hex = '{0:X6}' -f $st
        Write-Log DEBUG ('av: {0} productState=0x{1}' -f $name, $hex)
        $list += [pscustomobject]@{ Name = $name; On = ($hex.Substring(2, 1) -eq '1'); Old = ($hex.Substring(4, 2) -ne '00') }
    }
    if (-not $list.Count) {
        try { if ((Get-Service WinDefend -ErrorAction Stop).Status -eq 'Running') { $list = @([pscustomobject]@{ Name = 'Windows Defender'; On = $true; Old = $false }) } } catch { }
    }
    $act = @($list | Where-Object { $_.On })
    $names = @($(if ($act.Count) { $act } else { $list }) | ForEach-Object { $_.Name } | Select-Object -Unique)
    $script:LastAvNames = $names
    $third = (@($act | Where-Object { $_.Name -notmatch 'Defender' }).Count -gt 0)
    if (-not $list.Count) {
        $c = New-Check 'warn' (U '\u0410\u043d\u0442\u0438\u0432\u0438\u0440\u0443\u0441 \u043d\u0435 \u043e\u0431\u043d\u0430\u0440\u0443\u0436\u0435\u043d') (U '\u041f\u0440\u043e\u0432\u0435\u0440\u0438\u0442\u044c \u0437\u0430\u0449\u0438\u0442\u0443 \u0432\u0440\u0443\u0447\u043d\u0443\u044e (\u043d\u0430 \u0441\u0435\u0440\u0432\u0435\u0440\u0430\u0445 \u0438 \u0441 \u043d\u0435\u0441\u0442\u0430\u043d\u0434\u0430\u0440\u0442\u043d\u043e\u0439 \u0437\u0430\u0449\u0438\u0442\u043e\u0439 \u0441\u0432\u0435\u0434\u0435\u043d\u0438\u044f \u043c\u043e\u0433\u0443\u0442 \u0431\u044b\u0442\u044c \u043d\u0435\u0434\u043e\u0441\u0442\u0443\u043f\u043d\u044b)') (U '\u041d\u0435\u0442 \u0430\u043d\u0442\u0438\u0432\u0438\u0440\u0443\u0441\u0430')
    }
    elseif (-not $act.Count) {
        $c = New-Check 'bad' ((U '\u0410\u043d\u0442\u0438\u0432\u0438\u0440\u0443\u0441 \u0435\u0441\u0442\u044c, \u043d\u043e \u0432\u044b\u043a\u043b\u044e\u0447\u0435\u043d: ') + ($names -join ', ')) (U '\u0412\u043a\u043b\u044e\u0447\u0438\u0442\u044c \u0437\u0430\u0449\u0438\u0442\u0443') (U '\u0410\u043d\u0442\u0438\u0432\u0438\u0440\u0443\u0441 \u0432\u044b\u043a\u043b\u044e\u0447\u0435\u043d')
    }
    elseif (@($act | Where-Object { $_.Old }).Count) {
        $c = New-Check 'warn' ((U '\u0410\u043d\u0442\u0438\u0432\u0438\u0440\u0443\u0441: ') + ($names -join ', ') + (U ' \u2014 \u0431\u0430\u0437\u044b \u0443\u0441\u0442\u0430\u0440\u0435\u043b\u0438')) (U '\u041e\u0431\u043d\u043e\u0432\u0438\u0442\u044c \u0430\u043d\u0442\u0438\u0432\u0438\u0440\u0443\u0441\u043d\u044b\u0435 \u0431\u0430\u0437\u044b') (U '\u0411\u0430\u0437\u044b \u0430\u043d\u0442\u0438\u0432\u0438\u0440\u0443\u0441\u0430 \u0443\u0441\u0442\u0430\u0440\u0435\u043b\u0438')
    }
    else { $c = New-Check 'ok' ((U '\u0410\u043d\u0442\u0438\u0432\u0438\u0440\u0443\u0441: ') + ($names -join ', ')) }
    [pscustomobject]@{ Check = $c; Third = $third }
}

# Get-NetFirewallProfile is missing on Windows 7: fall back to the registry policy keys; unknown -> no check (nothing is invented)
function Get-FirewallCheck([bool]$thirdPartyAv) {
    $off = $null
    try { $off = @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { "$($_.Enabled)" -eq 'False' } | ForEach-Object { [string]$_.Name }) }
    catch { Write-Log DEBUG "report: Get-NetFirewallProfile unavailable: $($_.Exception.Message)" }
    $total = 3
    if ($null -eq $off) {
        $off = @(); $seen = 0
        $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\'
        foreach ($pr in @(@('DomainProfile', 'Domain'), @('StandardProfile', 'Private'), @('PublicProfile', 'Public'))) {
            try {
                $v = (Get-ItemProperty -LiteralPath ($base + $pr[0]) -ErrorAction Stop).EnableFirewall
                if ($null -ne $v) { $seen++; if ([int]$v -eq 0) { $off += $pr[1] } }
            } catch { Write-Log DEBUG "report: firewall registry $($pr[0]): $($_.Exception.Message)" }
        }
        if (-not $seen) { return $null }
    }
    if (-not $off.Count) { return (New-Check 'ok' (U '\u0411\u0440\u0430\u043d\u0434\u043c\u0430\u0443\u044d\u0440 Windows \u0432\u043a\u043b\u044e\u0447\u0451\u043d')) }
    $txt = (U '\u0411\u0440\u0430\u043d\u0434\u043c\u0430\u0443\u044d\u0440 Windows \u0432\u044b\u043a\u043b\u044e\u0447\u0435\u043d \u0432 \u043f\u0440\u043e\u0444\u0438\u043b\u044f\u0445: ') + ($off -join ', ')
    if ($thirdPartyAv) { return (New-Check 'warn' ($txt + (U ' (\u0432\u043e\u0437\u043c\u043e\u0436\u043d\u043e, \u0435\u0433\u043e \u0437\u0430\u043c\u0435\u043d\u044f\u0435\u0442 \u0441\u0442\u043e\u0440\u043e\u043d\u043d\u044f\u044f \u0437\u0430\u0449\u0438\u0442\u0430)')) (U '\u041f\u0440\u043e\u0432\u0435\u0440\u0438\u0442\u044c, \u0447\u0442\u043e \u0441\u0435\u0442\u0435\u0432\u0443\u044e \u0437\u0430\u0449\u0438\u0442\u0443 \u0432\u0435\u0434\u0451\u0442 \u0434\u0440\u0443\u0433\u0430\u044f \u043f\u0440\u043e\u0433\u0440\u0430\u043c\u043c\u0430') (U '\u0411\u0440\u0430\u043d\u0434\u043c\u0430\u0443\u044d\u0440 \u0432\u044b\u043a\u043b\u044e\u0447\u0435\u043d')) }
    $lvl = $(if ($off.Count -ge $total) { 'bad' } else { 'warn' })
    New-Check $lvl $txt (U '\u0412\u043a\u043b\u044e\u0447\u0438\u0442\u044c \u0431\u0440\u0430\u043d\u0434\u043c\u0430\u0443\u044d\u0440 Windows') (U '\u0411\u0440\u0430\u043d\u0434\u043c\u0430\u0443\u044d\u0440 \u0432\u044b\u043a\u043b\u044e\u0447\u0435\u043d')
}

function Get-SysDiskCheck($v) {
    $thrBad = [int](Cfg 'checks.diskFreePctBad' 10); $thrWarn = [int](Cfg 'checks.diskFreePctWarn' 20); $gbBad = [double](Cfg 'checks.diskFreeGbBad' 5)
    $pct = [int][math]::Round(100 * $v.FreeSpace / $v.Size); $gb = [math]::Round($v.FreeSpace / 1GB, 1)
    $txt = ((U '\u0421\u0432\u043e\u0431\u043e\u0434\u043d\u043e \u043d\u0430 \u0441\u0438\u0441\u0442\u0435\u043c\u043d\u043e\u043c \u0434\u0438\u0441\u043a\u0435: {0} \u0413\u0411 ({1}%)') -f $gb, $pct)
    $act = U '\u041e\u0447\u0438\u0441\u0442\u0438\u0442\u044c \u0434\u0438\u0441\u043a (\u0432\u0440\u0435\u043c\u0435\u043d\u043d\u044b\u0435 \u0444\u0430\u0439\u043b\u044b, \u043d\u0435\u043d\u0443\u0436\u043d\u044b\u0435 \u043f\u0440\u043e\u0433\u0440\u0430\u043c\u043c\u044b) \u0438\u043b\u0438 \u0437\u0430\u043c\u0435\u043d\u0438\u0442\u044c \u043d\u0430 \u0431\u043e\u043b\u044c\u0448\u0438\u0439'
    if ($pct -lt $thrBad -or $gb -lt $gbBad) { return (New-Check 'bad' ((U '\u0421\u0438\u0441\u0442\u0435\u043c\u043d\u044b\u0439 \u0434\u0438\u0441\u043a \u043f\u043e\u0447\u0442\u0438 \u0437\u0430\u043f\u043e\u043b\u043d\u0435\u043d. ') + $txt) $act ((U '\u041c\u0430\u043b\u043e \u043c\u0435\u0441\u0442\u0430 \u043d\u0430 ') + $env:SystemDrive + ' (' + $pct + '% ' + (U '\u0441\u0432\u043e\u0431.') + ')')) }
    if ($pct -lt $thrWarn) { return (New-Check 'warn' ((U '\u041d\u0430 \u0441\u0438\u0441\u0442\u0435\u043c\u043d\u043e\u043c \u0434\u0438\u0441\u043a\u0435 \u043c\u0430\u043b\u043e \u043c\u0435\u0441\u0442\u0430. ') + $txt) $act ((U '\u041c\u0430\u043b\u043e \u043c\u0435\u0441\u0442\u0430 \u043d\u0430 ') + $env:SystemDrive + ' (' + $pct + '% ' + (U '\u0441\u0432\u043e\u0431.') + ')')) }
    New-Check 'ok' $txt
}

function Get-QuickChecks($os, $up, [double]$ramTotal) {
    $r = @()
    $upWarn = [int](Cfg 'checks.uptimeDaysWarn' 30)
    if ($up.TotalDays -gt 20000) { Write-Log DEBUG 'report: boot time unknown, uptime check skipped' }
    elseif ($up.Days -gt $upWarn) { $r += (New-Check 'warn' ((U '\u041a\u043e\u043c\u043f\u044c\u044e\u0442\u0435\u0440 \u043d\u0435 \u043f\u0435\u0440\u0435\u0437\u0430\u0433\u0440\u0443\u0436\u0430\u043b\u0441\u044f ') + $up.Days + (U ' \u0434\u043d.')) (U '\u041f\u0435\u0440\u0435\u0437\u0430\u0433\u0440\u0443\u0437\u0438\u0442\u044c \u041f\u041a (\u043f\u0440\u0438\u043c\u0435\u043d\u044f\u0442\u0441\u044f \u043e\u0431\u043d\u043e\u0432\u043b\u0435\u043d\u0438\u044f, \u043e\u0441\u0432\u043e\u0431\u043e\u0436\u0434\u0430\u0435\u0442\u0441\u044f \u043f\u0430\u043c\u044f\u0442\u044c)') ((U '\u0411\u0435\u0437 \u043f\u0435\u0440\u0435\u0437\u0430\u0433\u0440\u0443\u0437\u043a\u0438 ') + $up.Days + (U ' \u0434\u043d.'))) }
    else { $r += (New-Check 'ok' ((U '\u0412\u0440\u0435\u043c\u044f \u0440\u0430\u0431\u043e\u0442\u044b \u0431\u0435\u0437 \u043f\u0435\u0440\u0435\u0437\u0430\u0433\u0440\u0443\u0437\u043a\u0438: ') + $up.Days + (U ' \u0434\u043d.'))) }
    $ramWarn = [double](Cfg 'checks.ramGbWarn' 4)
    if ($ramTotal -le 0) { Write-Log DEBUG 'report: RAM size unknown, RAM check skipped' }
    elseif ($ramTotal -lt $ramWarn) { $r += (New-Check 'warn' ((U '\u041c\u0430\u043b\u043e \u043e\u043f\u0435\u0440\u0430\u0442\u0438\u0432\u043d\u043e\u0439 \u043f\u0430\u043c\u044f\u0442\u0438: ') + $ramTotal + (U ' \u0413\u0411')) (U '\u0414\u043e\u0431\u0430\u0432\u0438\u0442\u044c \u043f\u0430\u043c\u044f\u0442\u044c, \u0435\u0441\u043b\u0438 \u041f\u041a \u0440\u0430\u0431\u043e\u0442\u0430\u0435\u0442 \u043c\u0435\u0434\u043b\u0435\u043d\u043d\u043e') ((U '\u041c\u0430\u043b\u043e \u041e\u0417\u0423: ') + $ramTotal + (U ' \u0413\u0411'))) }
    else { $r += (New-Check 'ok' ((U '\u041e\u043f\u0435\u0440\u0430\u0442\u0438\u0432\u043d\u043e\u0439 \u043f\u0430\u043c\u044f\u0442\u0438 \u0434\u043e\u0441\u0442\u0430\u0442\u043e\u0447\u043d\u043e: ') + $ramTotal + (U ' \u0413\u0411'))) }
    $oc = Get-OsSupportCheck $os; if ($oc) { $r += $oc }
    $av = Get-AvCheck; $r += $av.Check
    $fw = Get-FirewallCheck $av.Third; if ($fw) { $r += $fw }
    $r
}

function ConvertTo-CheckHtml($checks) {
    $lbl = @{ bad = (U '\u0418\u0441\u043f\u0440\u0430\u0432\u0438\u0442\u044c'); warn = (U '\u0412\u043d\u0438\u043c\u0430\u043d\u0438\u0435'); ok = (U '\u041d\u043e\u0440\u043c\u0430') }
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append('<ul class="checks">')
    foreach ($lv in 'bad', 'warn', 'ok') {
        foreach ($c in @($checks | Where-Object { $_.L -eq $lv })) {
            $a = ''; if ($c.A -and $lv -ne 'ok') { $a = '<small class="act">' + (Enc $c.A) + '</small>' }
            [void]$sb.Append('<li class="' + $lv + '"><i aria-hidden="true"></i><span class="lv">' + $lbl[$lv] + '</span><span class="tx">' + (Enc $c.T) + $a + '</span></li>')
        }
    }
    [void]$sb.Append('</ul>')
    $sb.ToString()
}

# one-line answer to "what to fix first"
function Get-CheckLead($checks) {
    $f = @($checks | Where-Object { $_.L -eq 'bad' } | Select-Object -First 1)
    $lv = 'bad'
    if (-not $f.Count) { $f = @($checks | Where-Object { $_.L -eq 'warn' } | Select-Object -First 1); $lv = 'warn' }
    if (-not $f.Count) { return '<p class="lead ok">' + (Enc (U '\u041a\u0440\u0438\u0442\u0438\u0447\u043d\u044b\u0445 \u043f\u0440\u043e\u0431\u043b\u0435\u043c \u043d\u0435 \u043d\u0430\u0439\u0434\u0435\u043d\u043e')) + '</p>' }
    $t = (U '\u0421\u043d\u0430\u0447\u0430\u043b\u0430: ') + $f[0].T
    if ($f[0].A) { $t += ' - ' + $f[0].A }
    '<p class="lead ' + $lv + '">' + (Enc $t) + '</p>'
}

# ---- state column: three categories, short real reasons ----
#   red    "Danger: ..."      - something dangerous (nearly full system disk, unsupported OS, no / disabled antivirus, ...)
#   yellow "Tolerable: ..."   - not great, but it can be lived with (little free space, long uptime, little RAM, ...)
#   green  "No problems"      - nothing found
# The reason always says WHAT it is (low free space on the system drive, low RAM), so it cannot be mistaken for disk health.
function Get-StateLabel([string]$level) {
    switch ($level) { 'bad' { U '\u041e\u043f\u0430\u0441\u043d\u043e' } 'warn' { U '\u0422\u0435\u0440\u043f\u0438\u043c\u043e' } default { U '\u041d\u0435\u0442 \u043f\u0440\u043e\u0431\u043b\u0435\u043c' } }
}
function Get-DefaultState { [string](Cfg 'excel.defaultState' (Get-StateLabel 'ok')) }
function Get-StateSummary($checks) {
    $maxItems = [Math]::Max(1, [int](Cfg 'excel.stateMaxItems' 2))
    $bad  = @($checks | Where-Object { $_.L -eq 'bad'  -and $_.S } | ForEach-Object { $_.S })
    $warn = @($checks | Where-Object { $_.L -eq 'warn' -and $_.S } | ForEach-Object { $_.S })
    $all  = @($bad + $warn)
    if (-not $all.Count) { return (Get-DefaultState) }
    $label = if ($bad.Count) { Get-StateLabel 'bad' } else { Get-StateLabel 'warn' }
    $txt = $label + ': ' + ((@($all | Select-Object -First $maxItems)) -join ', ')
    if ($all.Count -gt $maxItems) { $txt += ' +' + ($all.Count - $maxItems) }
    $txt
}
# true when the cell text was produced by this tool (new or legacy wording) and may be refreshed; a hand-written note is never replaced
function Test-AutoState([string]$s) {
    if (-not $s) { return $true }
    $s = $s.Trim()
    if ($s -ieq (Get-DefaultState)) { return $true }
    foreach ($w in @((Get-StateLabel 'bad'), (Get-StateLabel 'warn'), (Get-StateLabel 'ok'), (U '\u041f\u043b\u043e\u0445\u043e\u0435'), (U '\u0412\u043d\u0438\u043c\u0430\u043d\u0438\u0435'), (U '\u0425\u043e\u0440\u043e\u0448\u0435\u0435'))) {
        if ($s -ieq $w -or $s.StartsWith($w + ':')) { return $true }
    }
    $false
}

# ===================== REPORT (pure WMI/CIM, self-contained HTML) =====================
function Enc($s) { [System.Net.WebUtility]::HtmlEncode(([string]$s).Trim()) }
function Icon([string]$n) {
    $p = @{
        cpu    = '<rect x="6" y="6" width="12" height="12" rx="2"/><path d="M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"/>'
        ram    = '<rect x="2" y="7" width="20" height="10" rx="2"/><path d="M6 11v2M10 11v2M14 11v2M18 11v2"/>'
        disk   = '<ellipse cx="12" cy="6" rx="8" ry="3"/><path d="M4 6v6c0 1.7 3.6 3 8 3s8-1.3 8-3V6M4 12v6c0 1.7 3.6 3 8 3s8-1.3 8-3v-6"/>'
        gpu    = '<rect x="2" y="6" width="20" height="11" rx="2"/><circle cx="9" cy="11.5" r="2.5"/><path d="M15 9h4M15 12h4M6 20h12"/>'
        net    = '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c3 3.5 3 14.5 0 18M12 3c-3 3.5-3 14.5 0 18"/>'
        shield = '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/><path d="M9 12l2 2 4-4"/>'
        apps   = '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>'
        info   = '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.01"/>'
        pulse  = '<path d="M3 12h4l3-7 4 14 3-7h4"/>'
    }
    '<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">' + $p[$n] + '</svg>'
}
function Card([string]$title, [string]$icon, [string]$body, [string]$cls = '') {
    '<section class="card ' + $cls + '"><h2>' + (Icon $icon) + '<span>' + $title + '</span></h2>' + $body + '</section>'
}
function HtmlTbl($rows, [string]$id = '') {
    $rows = @($rows | Where-Object { $_ })
    if (-not $rows) { return '<p class="muted">' + (U '\u041d\u0435\u0442 \u0434\u0430\u043d\u043d\u044b\u0445') + '</p>' }
    $cols = $rows[0].PSObject.Properties.Name
    $h = '<div class="scroll"><table class="tbl"' + $(if ($id) { ' id="' + $id + '"' } else { '' }) + '><thead><tr>' + (($cols | ForEach-Object { '<th>' + (Enc $_) + '</th>' }) -join '') + '</tr></thead><tbody>'
    foreach ($r in $rows) { $h += '<tr>' + (($cols | ForEach-Object { '<td>' + (Enc $r.$_) + '</td>' }) -join '') + '</tr>' }
    $h + '</tbody></table></div>'
}
function KvList($pairs) {
    '<dl class="kv">' + (($pairs.GetEnumerator() | Where-Object { "$($_.Value)".Trim() } | ForEach-Object { '<div><dt>' + (Enc $_.Key) + '</dt><dd>' + (Enc $_.Value) + '</dd></div>' }) -join '') + '</dl>'
}

function New-InspectorReport($path) {
    $cs   = Get-CimSafe Win32_ComputerSystem
    $os   = Get-CimSafe Win32_OperatingSystem
    $bb   = Get-CimSafe Win32_BaseBoard
    $bios = Get-CimSafe Win32_BIOS
    $skipDisk = -1
    try { $skipDisk = (Get-Partition -DriveLetter $Drive.TrimEnd(':') | Get-Disk).Number } catch { Write-Log DEBUG "report: cannot tell which disk is the USB drive: $($_.Exception.Message)" }
    $up = (Get-Date) - $os.LastBootUpTime
    $checks = New-Object System.Collections.ArrayList
    $add = { param($lvl, $txt) [void]$checks.Add([pscustomobject]@{ L = $lvl; T = $txt }) }

    # ---- hardware ----
    $cpuRows = @(Get-CimSafe Win32_Processor)
    $cpuName = ($cpuRows | Select-Object -First 1).Name -replace '\s+', ' '
    $cpu = $cpuRows | Select-Object @{n = (U '\u041f\u0440\u043e\u0446\u0435\u0441\u0441\u043e\u0440'); e = { $_.Name -replace '\s+', ' ' } }, @{n = (U '\u042f\u0434\u0435\u0440'); e = { $_.NumberOfCores } }, @{n = (U '\u041f\u043e\u0442\u043e\u043a\u043e\u0432'); e = { $_.NumberOfLogicalProcessors } }, @{n = (U '\u041c\u0413\u0446'); e = { $_.MaxClockSpeed } }
    $mem = @(Get-CimSafe Win32_PhysicalMemory)
    $ramTotal = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    $ram = $mem | Select-Object @{n = (U '\u0421\u043b\u043e\u0442'); e = { $_.BankLabel } }, @{n = (U '\u041f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0438\u0442\u0435\u043b\u044c'); e = { $_.Manufacturer } }, @{n = (U '\u041f\u0430\u0440\u0442-\u043d\u043e\u043c\u0435\u0440'); e = { $_.PartNumber } }, @{n = (U '\u0413\u0411'); e = { [math]::Round($_.Capacity / 1GB, 1) } }, @{n = (U '\u041c\u0413\u0446'); e = { $_.Speed } }
    $dsk = $null
    try {
        $dsk = @(Get-PhysicalDisk -ErrorAction Stop | Where-Object { [int]$_.DeviceId -ne $skipDisk } | Select-Object @{n = (U '\u041c\u043e\u0434\u0435\u043b\u044c'); e = { $_.FriendlyName } }, @{n = (U '\u0422\u0438\u043f'); e = { $_.MediaType } }, @{n = (U '\u0421\u043e\u0441\u0442\u043e\u044f\u043d\u0438\u0435'); e = { $_.HealthStatus } }, @{n = (U '\u0413\u0411'); e = { [math]::Round($_.Size / 1GB) } }, @{n = (U '\u0428\u0438\u043d\u0430'); e = { $_.BusType } })
        foreach ($d in $dsk) { if ("$($d.(U '\u0421\u043e\u0441\u0442\u043e\u044f\u043d\u0438\u0435'))" -notmatch 'Healthy|^$') { & $add 'bad' ((U '\u041d\u0430\u043a\u043e\u043f\u0438\u0442\u0435\u043b\u044c \u0441\u043e\u043e\u0431\u0449\u0430\u0435\u0442 \u043e \u043f\u0440\u043e\u0431\u043b\u0435\u043c\u0435: ') + $d.(U '\u041c\u043e\u0434\u0435\u043b\u044c')) } }
    } catch {
        $dsk = @(Get-CimSafe Win32_DiskDrive | Where-Object { $_.Index -ne $skipDisk } | Select-Object @{n = (U '\u041c\u043e\u0434\u0435\u043b\u044c'); e = { $_.Model } }, @{n = (U '\u0421\u043e\u0441\u0442\u043e\u044f\u043d\u0438\u0435'); e = { $_.Status } }, @{n = (U '\u0413\u0411'); e = { [math]::Round($_.Size / 1GB) } }, @{n = (U '\u0428\u0438\u043d\u0430'); e = { $_.InterfaceType } })
        foreach ($d in $dsk) { if ("$($d.(U '\u0421\u043e\u0441\u0442\u043e\u044f\u043d\u0438\u0435'))" -notmatch '^OK$|^$') { & $add 'bad' ((U '\u041d\u0430\u043a\u043e\u043f\u0438\u0442\u0435\u043b\u044c \u0441\u043e\u043e\u0431\u0449\u0430\u0435\u0442 \u043e \u043f\u0440\u043e\u0431\u043b\u0435\u043c\u0435: ') + $d.(U '\u041c\u043e\u0434\u0435\u043b\u044c')) } }
    }
    $vols = @(Get-CimSafe Win32_LogicalDisk -Filter 'DriveType=3')
    $volHtml = ''
    foreach ($v in $vols) {
        if (-not $v.Size) { continue }
        $usedPct = [int][math]::Round(100 * ($v.Size - $v.FreeSpace) / $v.Size)
        $freePct = 100 - $usedPct
        $cls = if ($freePct -lt 10) { 'bad' } elseif ($freePct -lt 20) { 'warn' } else { 'ok' }
        $lbl = (Enc $v.DeviceID) + $(if ($v.VolumeName) { ' &middot; ' + (Enc $v.VolumeName) } else { '' })
        $volHtml += '<div class="vol"><div class="vol-h"><b>' + $lbl + '</b><span>' + (Enc $v.FileSystem) + ' &middot; ' + (U '\u0441\u0432\u043e\u0431\u043e\u0434\u043d\u043e ') + [math]::Round($v.FreeSpace / 1GB) + ' / ' + [math]::Round($v.Size / 1GB) + ' ' + (U '\u0413\u0411') + '</span></div><div class="bar"><i class="' + $cls + '" style="width:' + $usedPct + '%"></i></div></div>'
        if ($v.DeviceID -eq $env:SystemDrive) {
            if ($freePct -lt 10) { & $add 'bad' ((U '\u0421\u0438\u0441\u0442\u0435\u043c\u043d\u044b\u0439 \u0434\u0438\u0441\u043a \u043f\u043e\u0447\u0442\u0438 \u0437\u0430\u043f\u043e\u043b\u043d\u0435\u043d: \u0441\u0432\u043e\u0431\u043e\u0434\u043d\u043e ') + $freePct + '%') }
            elseif ($freePct -lt 20) { & $add 'warn' ((U '\u041d\u0430 \u0441\u0438\u0441\u0442\u0435\u043c\u043d\u043e\u043c \u0434\u0438\u0441\u043a\u0435 \u043c\u0430\u043b\u043e \u043c\u0435\u0441\u0442\u0430: \u0441\u0432\u043e\u0431\u043e\u0434\u043d\u043e ') + $freePct + '%') }
            else { & $add 'ok' ((U '\u041d\u0430 \u0441\u0438\u0441\u0442\u0435\u043c\u043d\u043e\u043c \u0434\u0438\u0441\u043a\u0435 \u0434\u043e\u0441\u0442\u0430\u0442\u043e\u0447\u043d\u043e \u043c\u0435\u0441\u0442\u0430: \u0441\u0432\u043e\u0431\u043e\u0434\u043d\u043e ') + $freePct + '%') }
        }
    }
    $gpu = Get-CimSafe Win32_VideoController | Where-Object { $_.Name -notmatch 'Parsec|Virtual|Remote|Mirror|Basic' } | Select-Object @{n = (U '\u0412\u0438\u0434\u0435\u043e\u0430\u0434\u0430\u043f\u0442\u0435\u0440'); e = { $_.Name } }, @{n = (U '\u0414\u0440\u0430\u0439\u0432\u0435\u0440'); e = { $_.DriverVersion } }
    $net = Get-CimSafe Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=true' | Select-Object @{n = (U '\u0410\u0434\u0430\u043f\u0442\u0435\u0440'); e = { $_.Description } }, @{n = 'MAC'; e = { $_.MACAddress } }, @{n = 'IP'; e = { $_.IPAddress -join ', ' } }, @{n = (U '\u0428\u043b\u044e\u0437'); e = { $_.DefaultIPGateway -join ', ' } }
    $bat = Get-CimSafe Win32_Battery -ErrorAction SilentlyContinue | Select-Object @{n = (U '\u0411\u0430\u0442\u0430\u0440\u0435\u044f'); e = { $_.Name } }, @{n = (U '\u0417\u0430\u0440\u044f\u0434, %'); e = { $_.EstimatedChargeRemaining } }

    # ---- checks ----
    if ($up.Days -gt 30) { & $add 'warn' ((U '\u041a\u043e\u043c\u043f\u044c\u044e\u0442\u0435\u0440 \u043d\u0435 \u043f\u0435\u0440\u0435\u0437\u0430\u0433\u0440\u0443\u0436\u0430\u043b\u0441\u044f ') + $up.Days + (U ' \u0434\u043d., \u0440\u0435\u043a\u043e\u043c\u0435\u043d\u0434\u0443\u0435\u0442\u0441\u044f \u043f\u0435\u0440\u0435\u0437\u0430\u0433\u0440\u0443\u0437\u043a\u0430')) } else { & $add 'ok' ((U '\u0412\u0440\u0435\u043c\u044f \u0440\u0430\u0431\u043e\u0442\u044b \u0431\u0435\u0437 \u043f\u0435\u0440\u0435\u0437\u0430\u0433\u0440\u0443\u0437\u043a\u0438: ') + $up.Days + (U ' \u0434\u043d.')) }
    if ($ramTotal -lt 4) { & $add 'warn' ((U '\u041c\u0430\u043b\u043e \u043e\u043f\u0435\u0440\u0430\u0442\u0438\u0432\u043d\u043e\u0439 \u043f\u0430\u043c\u044f\u0442\u0438: ') + $ramTotal + (U ' \u0413\u0411')) } else { & $add 'ok' ((U '\u041e\u043f\u0435\u0440\u0430\u0442\u0438\u0432\u043d\u043e\u0439 \u043f\u0430\u043c\u044f\u0442\u0438 \u0434\u043e\u0441\u0442\u0430\u0442\u043e\u0447\u043d\u043e: ') + $ramTotal + (U ' \u0413\u0411')) }
    if ($os.Caption -match 'Windows (7|8|Vista|XP)|2003|2008|Server 2012') { & $add 'bad' ((U '\u0423\u0441\u0442\u0430\u0440\u0435\u0432\u0448\u0430\u044f \u041e\u0421 \u0431\u0435\u0437 \u043f\u043e\u0434\u0434\u0435\u0440\u0436\u043a\u0438: ') + $os.Caption) } else { & $add 'ok' (U '\u041e\u0421 \u043f\u043e\u0434\u0434\u0435\u0440\u0436\u0438\u0432\u0430\u0435\u0442\u0441\u044f \u043f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0438\u0442\u0435\u043b\u0435\u043c') }
    $av = @(); try { $av = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop | Select-Object -ExpandProperty displayName) } catch { Write-Log DEBUG "report: SecurityCenter2 unavailable: $($_.Exception.Message)" }
    if (-not $av -and ((Get-Service WinDefend -ErrorAction SilentlyContinue).Status -eq 'Running')) { $av = @('Windows Defender') }
    if ($av) { & $add 'ok' ((U '\u0410\u043d\u0442\u0438\u0432\u0438\u0440\u0443\u0441: ') + (($av | Select-Object -Unique) -join ', ')) } else { & $add 'warn' (U '\u0410\u043d\u0442\u0438\u0432\u0438\u0440\u0443\u0441 \u043d\u0435 \u043e\u0431\u043d\u0430\u0440\u0443\u0436\u0435\u043d') }
    $fwOff = $null; try { $fwOff = @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { "$($_.Enabled)" -eq 'False' } | ForEach-Object { $_.Name }) } catch { Write-Log DEBUG "report: Get-NetFirewallProfile unavailable: $($_.Exception.Message)" }
    if ($null -ne $fwOff) { if ($fwOff.Count) { & $add 'warn' ((U '\u0411\u0440\u0430\u043d\u0434\u043c\u0430\u0443\u044d\u0440 \u0432\u044b\u043a\u043b\u044e\u0447\u0435\u043d \u0432 \u043f\u0440\u043e\u0444\u0438\u043b\u044f\u0445: ') + ($fwOff -join ', ')) } else { & $add 'ok' (U '\u0411\u0440\u0430\u043d\u0434\u043c\u0430\u0443\u044d\u0440 Windows \u0432\u043a\u043b\u044e\u0447\u0451\u043d') } }
    $nOk = @($checks | Where-Object L -eq 'ok').Count; $nWarn = @($checks | Where-Object L -eq 'warn').Count; $nBad = @($checks | Where-Object L -eq 'bad').Count
    $checkHtml = '<ul class="checks">' + (($checks | Sort-Object @{e = { @{ bad = 0; warn = 1; ok = 2 }[$_.L] } } | ForEach-Object { '<li class="' + $_.L + '"><i></i><span>' + (Enc $_.T) + '</span></li>' }) -join '') + '</ul>'

    # ---- software (from uninstall entries, system components and updates hidden) ----
    $sw = @(Get-Uninstall | Where-Object { $_.SystemComponent -ne 1 -and -not $_.ParentKeyName } |
        Sort-Object DisplayName | Select-Object -Property @{n = (U '\u041f\u0440\u043e\u0433\u0440\u0430\u043c\u043c\u0430'); e = { $_.DisplayName } }, @{n = (U '\u0412\u0435\u0440\u0441\u0438\u044f'); e = { $_.DisplayVersion } }, @{n = (U '\u0418\u0437\u0434\u0430\u0442\u0435\u043b\u044c'); e = { $_.Publisher } } -Unique)

    # ---- page ----
    $general = [ordered]@{}
    $general[(U '\u041a\u043e\u043c\u043f\u044c\u044e\u0442\u0435\u0440')] = $env:COMPUTERNAME; $general[(U '\u041f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0438\u0442\u0435\u043b\u044c')] = $cs.Manufacturer; $general[(U '\u041c\u043e\u0434\u0435\u043b\u044c')] = $cs.Model
    $general[(U '\u0421\u0435\u0440\u0438\u0439\u043d\u044b\u0439 \u043d\u043e\u043c\u0435\u0440')] = $bios.SerialNumber; $general[(U '\u0421\u0438\u0441\u0442\u0435\u043c\u043d\u0430\u044f \u043f\u043b\u0430\u0442\u0430')] = "$($bb.Manufacturer) $($bb.Product)"; $general['BIOS'] = $bios.SMBIOSBIOSVersion
    $general[(U '\u041e\u043f\u0435\u0440\u0430\u0446\u0438\u043e\u043d\u043d\u0430\u044f \u0441\u0438\u0441\u0442\u0435\u043c\u0430')] = "$($os.Caption) ($($os.OSArchitecture)), build $($os.BuildNumber)"; $general[(U '\u0423\u0441\u0442\u0430\u043d\u043e\u0432\u043b\u0435\u043d\u0430')] = $os.InstallDate.ToString('yyyy-MM-dd')
    $general[(U '\u0412\u0440\u0435\u043c\u044f \u0440\u0430\u0431\u043e\u0442\u044b')] = ('{0} {1} {2} {3}' -f $up.Days, (U '\u0434'), $up.Hours, (U '\u0447')); $general[(U '\u0414\u043e\u043c\u0435\u043d / \u0440\u0430\u0431\u043e\u0447\u0430\u044f \u0433\u0440\u0443\u043f\u043f\u0430')] = $cs.Domain; $general[(U '\u041f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u0435\u043b\u044c')] = $cs.UserName
    $sysVol = $vols | Where-Object { $_.DeviceID -eq $env:SystemDrive } | Select-Object -First 1
    $sysFree = if ($sysVol -and $sysVol.Size) { [string][math]::Round($sysVol.FreeSpace / 1GB) + ' ' + (U '\u0413\u0411 \u0441\u0432\u043e\u0431\u043e\u0434\u043d\u043e') } else { '-' }
    $chips = '<span class="chip">' + (Enc $cpuName) + '</span><span class="chip">' + $ramTotal + ' ' + (U '\u0413\u0411 \u041e\u0417\u0423') + '</span><span class="chip">' + (Enc $sysFree) + '</span><span class="chip">' + (Enc $os.Caption) + '</span>'
    $summary = "$env:COMPUTERNAME | $($cs.Manufacturer) $($cs.Model) | $cpuName | $ramTotal GB RAM | $($os.Caption)"
    $stat = '<div class="stats"><div class="st ok"><b>' + $nOk + '</b><span>' + (U '\u0432 \u043d\u043e\u0440\u043c\u0435') + '</span></div><div class="st warn"><b>' + $nWarn + '</b><span>' + (U '\u0432\u043d\u0438\u043c\u0430\u043d\u0438\u0435') + '</span></div><div class="st bad"><b>' + $nBad + '</b><span>' + (U '\u043f\u0440\u043e\u0431\u043b\u0435\u043c\u044b') + '</span></div></div>'

    $body  = (Card (U '\u0411\u044b\u0441\u0442\u0440\u0430\u044f \u043f\u0440\u043e\u0432\u0435\u0440\u043a\u0430') 'pulse' ($stat + $checkHtml) 'wide')
    $body += (Card (U '\u0421\u0438\u0441\u0442\u0435\u043c\u0430') 'info' (KvList $general))
    $body += (Card (U '\u041f\u0440\u043e\u0446\u0435\u0441\u0441\u043e\u0440') 'cpu' (HtmlTbl $cpu))
    $body += (Card ((U '\u041e\u043f\u0435\u0440\u0430\u0442\u0438\u0432\u043d\u0430\u044f \u043f\u0430\u043c\u044f\u0442\u044c') + " ($ramTotal " + (U '\u0413\u0411') + ')') 'ram' (HtmlTbl $ram))
    $body += (Card (U '\u041d\u0430\u043a\u043e\u043f\u0438\u0442\u0435\u043b\u0438 \u0438 \u0442\u043e\u043c\u0430') 'disk' ((HtmlTbl $dsk) + '<div class="vols">' + $volHtml + '</div>') 'wide')
    $body += (Card (U '\u0412\u0438\u0434\u0435\u043e\u0430\u0434\u0430\u043f\u0442\u0435\u0440') 'gpu' (HtmlTbl $gpu))
    $body += (Card (U '\u0421\u0435\u0442\u044c') 'net' (HtmlTbl $net))
    if ($bat) { $body += (Card (U '\u0411\u0430\u0442\u0430\u0440\u0435\u044f') 'pulse' (HtmlTbl $bat)) }
    $body += (Card ((U '\u0423\u0441\u0442\u0430\u043d\u043e\u0432\u043b\u0435\u043d\u043d\u044b\u0435 \u043f\u0440\u043e\u0433\u0440\u0430\u043c\u043c\u044b') + " ($($sw.Count))") 'apps' ('<input id="q" class="search" type="search" placeholder="' + (U '\u041f\u043e\u0438\u0441\u043a \u043f\u0440\u043e\u0433\u0440\u0430\u043c\u043c\u044b...') + '">' + (HtmlTbl $sw 'sw')) 'wide')

    $tpl = U @'
<!DOCTYPE html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{{PC}} - InspektorOfficEr</title>
<style>
:root{--bg:#f4f6fb;--card:#fff;--ink:#14182b;--mut:#6b7390;--line:#e4e8f2;--acc:#4f46e5;--acc2:#06b6d4;--ok:#16a34a;--warn:#d97706;--bad:#dc2626;--sh:0 1px 2px rgba(20,24,43,.05),0 8px 24px rgba(20,24,43,.06);color-scheme:light}
:root[data-theme=dark]{--bg:#0b0e1a;--card:#131830;--ink:#e8ebf7;--mut:#8b93b5;--line:#232a4a;--sh:0 1px 2px rgba(0,0,0,.4),0 8px 28px rgba(0,0,0,.35);color-scheme:dark}
@media(prefers-color-scheme:dark){:root:not([data-theme=light]){--bg:#0b0e1a;--card:#131830;--ink:#e8ebf7;--mut:#8b93b5;--line:#232a4a;--sh:0 1px 2px rgba(0,0,0,.4),0 8px 28px rgba(0,0,0,.35);color-scheme:dark}}
*{box-sizing:border-box}html,body{margin:0}body{background:var(--bg);color:var(--ink);font:14px/1.5 "Segoe UI Variable","Segoe UI",system-ui,Arial,sans-serif;-webkit-font-smoothing:antialiased}
.wrap{max-width:1180px;margin:0 auto;padding:0 20px 40px}
.top{display:flex;align-items:center;justify-content:space-between;padding:18px 0}
.brand{display:flex;align-items:center;gap:10px;font-weight:700;letter-spacing:.2px}.brand svg{width:34px;height:34px}.brand small{display:block;font-weight:500;color:var(--mut);font-size:11px;letter-spacing:.4px}
.btns{display:flex;gap:8px}.btn{appearance:none;border:1px solid var(--line);background:var(--card);color:var(--ink);padding:7px 12px;border-radius:10px;font:inherit;cursor:pointer;box-shadow:var(--sh)}.btn:hover{border-color:var(--acc)}
.hero{position:relative;overflow:hidden;border-radius:22px;padding:30px 30px 26px;color:#fff;background:linear-gradient(135deg,#4f46e5 0%,#7c3aed 48%,#06b6d4 100%);box-shadow:0 18px 50px rgba(79,70,229,.35)}
.hero:after{content:"";position:absolute;right:-60px;top:-60px;width:260px;height:260px;border-radius:50%;background:rgba(255,255,255,.12)}
.hero h1{margin:0 0 4px;font-size:34px;letter-spacing:.3px}.hero p{margin:0;opacity:.9}.chips{margin-top:16px;display:flex;flex-wrap:wrap;gap:8px;position:relative;z-index:1}
.chip{background:rgba(255,255,255,.18);backdrop-filter:blur(6px);border:1px solid rgba(255,255,255,.28);padding:5px 12px;border-radius:999px;font-size:12.5px}
.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px;margin-top:18px}
.card{background:var(--card);border:1px solid var(--line);border-radius:18px;padding:18px 20px;box-shadow:var(--sh);min-width:0}.card.wide{grid-column:1/-1}
.card h2{display:flex;align-items:center;gap:10px;margin:0 0 12px;font-size:15px}.ic{width:20px;height:20px;color:var(--acc)}
.kv{margin:0;display:grid;grid-template-columns:1fr 1fr;gap:4px 18px}.kv div{display:flex;flex-direction:column;padding:6px 0;border-bottom:1px dashed var(--line)}.kv dt{font-size:11.5px;color:var(--mut);text-transform:uppercase;letter-spacing:.4px}.kv dd{margin:0;word-break:break-word}
.scroll{overflow-x:auto}.tbl{width:100%;border-collapse:collapse}.tbl th{position:sticky;top:0;text-align:left;font-size:11.5px;color:var(--mut);text-transform:uppercase;letter-spacing:.4px;padding:8px 10px;border-bottom:1px solid var(--line);background:var(--card)}.tbl td{padding:8px 10px;border-bottom:1px solid var(--line)}.tbl tr:hover td{background:rgba(79,70,229,.06)}
.muted{color:var(--mut)}
.stats{display:flex;gap:12px;margin-bottom:12px;flex-wrap:wrap}.st{flex:1;min-width:110px;border-radius:14px;padding:10px 14px;border:1px solid var(--line)}.st b{font-size:26px;display:block;line-height:1.1}.st span{color:var(--mut);font-size:12px}
.st.ok b{color:var(--ok)}.st.warn b{color:var(--warn)}.st.bad b{color:var(--bad)}
.checks{list-style:none;margin:0;padding:0}.checks li{display:flex;align-items:center;gap:10px;padding:8px 0;border-bottom:1px solid var(--line)}.checks li:last-child{border:0}
.checks i{width:10px;height:10px;border-radius:50%;flex:none;background:var(--ok);box-shadow:0 0 0 4px rgba(22,163,74,.15)}.checks .warn i{background:var(--warn);box-shadow:0 0 0 4px rgba(217,119,6,.18)}.checks .bad i{background:var(--bad);box-shadow:0 0 0 4px rgba(220,38,38,.18)}
.vols{margin-top:14px;display:grid;gap:12px}.vol-h{display:flex;justify-content:space-between;gap:10px;margin-bottom:5px;flex-wrap:wrap}.vol-h span{color:var(--mut)}
.bar{height:10px;border-radius:99px;background:var(--line);overflow:hidden}.bar i{display:block;height:100%;border-radius:99px;background:var(--ok)}.bar i.warn{background:var(--warn)}.bar i.bad{background:var(--bad)}
.search{width:100%;margin-bottom:10px;padding:10px 14px;border-radius:12px;border:1px solid var(--line);background:var(--bg);color:var(--ink);font:inherit}.search:focus{outline:2px solid var(--acc);border-color:transparent}
#sw tbody tr.hide{display:none}
.foot{margin-top:26px;text-align:center;color:var(--mut);font-size:12px}.foot b{color:var(--ink)}
@media(max-width:820px){.grid{grid-template-columns:1fr}.kv{grid-template-columns:1fr}.hero h1{font-size:26px}}
@media print{body{background:#fff}.btns{display:none}.hero{box-shadow:none;-webkit-print-color-adjust:exact;print-color-adjust:exact}.card{box-shadow:none;break-inside:avoid}}
</style></head><body><div class="wrap">
<div class="top"><div class="brand"><svg viewBox="0 0 48 48"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#4f46e5"/><stop offset="1" stop-color="#06b6d4"/></linearGradient></defs><rect width="48" height="48" rx="12" fill="url(#g)"/><rect x="9" y="11" width="24" height="17" rx="3" fill="none" stroke="#fff" stroke-width="2.6"/><path d="M15 33h12" stroke="#fff" stroke-width="2.6" stroke-linecap="round"/><circle cx="32" cy="30" r="7" fill="#fff" fill-opacity=".18" stroke="#fff" stroke-width="2.6"/><path d="M37 35l5 5" stroke="#fff" stroke-width="3" stroke-linecap="round"/></svg><div>InspektorOfficEr<small>PC INSPECTION REPORT</small></div></div>
<div class="btns"><button class="btn" id="cp" data-s="{{SUMMARY}}">{{B_COPY}}</button><button class="btn" id="th">{{B_THEME}}</button><button class="btn" onclick="window.print()">{{B_PRINT}}</button></div></div>
<div class="hero"><h1>{{PC}}</h1><p>{{SUB}}</p><div class="chips">{{CHIPS}}</div></div>
<div class="grid">{{BODY}}</div>
<div class="foot">{{GENERATED}} {{DATE}} &middot; <b>InspektorOfficEr</b> v{{VER}}</div>
</div>
<script>
(function(){var r=document.documentElement;try{var t=localStorage.getItem("ioe-theme");if(t)r.setAttribute("data-theme",t)}catch(e){}
document.getElementById("th").onclick=function(){var d=r.getAttribute("data-theme");if(!d)d=window.matchMedia("(prefers-color-scheme:dark)").matches?"dark":"light";var n=d==="dark"?"light":"dark";r.setAttribute("data-theme",n);try{localStorage.setItem("ioe-theme",n)}catch(e){}};
var q=document.getElementById("q");if(q)q.oninput=function(){var v=q.value.toLowerCase();document.querySelectorAll("#sw tbody tr").forEach(function(tr){tr.classList.toggle("hide",tr.textContent.toLowerCase().indexOf(v)<0)})};
var c=document.getElementById("cp");c.onclick=function(){var s=c.getAttribute("data-s"),o=c.textContent;function ok(){c.textContent="OK";setTimeout(function(){c.textContent=o},1200)}
if(navigator.clipboard){navigator.clipboard.writeText(s).then(ok,ok)}else{var a=document.createElement("textarea");a.value=s;document.body.appendChild(a);a.select();try{document.execCommand("copy")}catch(e){}document.body.removeChild(a);ok()}};})();
</script></body></html>
'@
    $doc = $tpl.Replace('{{PC}}', (Enc $env:COMPUTERNAME)).Replace('{{SUB}}', (Enc "$($cs.Manufacturer) $($cs.Model)")).Replace('{{CHIPS}}', $chips).Replace('{{BODY}}', $body).Replace('{{SUMMARY}}', (Enc $summary)).Replace('{{DATE}}', (Get-Date -Format 'yyyy-MM-dd HH:mm')).Replace('{{VER}}', $AppVer).Replace('{{GENERATED}}', (U '\u041e\u0442\u0447\u0451\u0442 \u0441\u043e\u0437\u0434\u0430\u043d')).Replace('{{B_COPY}}', (U '\u041a\u043e\u043f\u0438\u0440\u043e\u0432\u0430\u0442\u044c \u0441\u0432\u043e\u0434\u043a\u0443')).Replace('{{B_THEME}}', (U '\u0422\u0435\u043c\u0430')).Replace('{{B_PRINT}}', (U '\u041f\u0435\u0447\u0430\u0442\u044c'))
    [IO.File]::WriteAllText($path, $doc, (New-Object Text.UTF8Encoding($true)))
}

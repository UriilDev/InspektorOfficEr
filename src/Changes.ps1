# ===================== CHANGES SINCE THE PREVIOUS REPORT OF THIS PC (snapshot in Service\state\<PC>.json) =====================
function Get-SnapshotFile { Join-Path (Join-Path $SvcDir 'state') ((([string]$env:COMPUTERNAME) -replace '[^\w\.-]', '_') + '.json') }

function Read-Snapshot {
    $f = Get-SnapshotFile
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try { return ([IO.File]::ReadAllText($f, [Text.Encoding]::UTF8) | ConvertFrom-Json) }
    catch { Write-Log WARN "snapshot is unreadable, comparison skipped: $($_.Exception.Message)"; return $null }
}

function Save-Snapshot($snap) {
    try {
        $f = Get-SnapshotFile
        New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
        [IO.File]::WriteAllText($f, ($snap | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($true)))
    } catch { Write-Log WARN "snapshot not saved: $($_.Exception.Message)" }
}

# $sw / $dsk are the report tables: first column = name, second = version (for software)
function New-Snapshot($os, [double]$ramTotal, $vols, $dsk, $sw) {
    $sv = @($vols | Where-Object { $_.DeviceID -eq $env:SystemDrive } | Select-Object -First 1)
    $free = 0; if ($sv.Count -and $sv[0].Size) { $free = [math]::Round($sv[0].FreeSpace / 1GB, 1) }
    $names = @(); $vers = @()
    foreach ($s in @($sw)) { $p = @($s.PSObject.Properties); $names += [string]$p[0].Value; $vers += [string]$p[1].Value }
    $dn = @(); foreach ($d in @($dsk)) { $p = @($d.PSObject.Properties); if ($p.Count) { $dn += [string]$p[0].Value } }
    [ordered]@{
        Date = (Get-Date -Format 'yyyy-MM-dd HH:mm'); Os = ('{0} build {1}' -f ([string]$os.Caption).Trim(), $os.BuildNumber)
        RamGb = $ramTotal; SysFreeGb = $free; Disks = $dn; Av = @($script:LastAvNames | Where-Object { $_ }); SwN = $names; SwV = $vers
    }
}

function Join-Limited($arr, [int]$max = 40) {
    $a = @($arr); $s = ($a | Select-Object -First $max) -join ', '
    if ($a.Count -gt $max) { $s += (U ' ... \u0438 \u0435\u0449\u0451 ') + ($a.Count - $max) }
    $s
}

function Get-ChangesHtml($old, $cur) {
    if (-not $old) { return '<p class="muted">' + (Enc (U '\u041f\u0435\u0440\u0432\u044b\u0439 \u043e\u0442\u0447\u0451\u0442 \u043f\u043e \u044d\u0442\u043e\u043c\u0443 \u041f\u041a: \u0441\u0440\u0430\u0432\u043d\u0438\u0432\u0430\u0442\u044c \u043f\u043e\u043a\u0430 \u043d\u0435 \u0441 \u0447\u0435\u043c.')) + '</p>' }
    $li = New-Object Collections.ArrayList
    $add = { param($h, $t) [void]$li.Add('<li><b>' + (Enc $h) + '</b>' + (Enc $t) + '</li>') }
    if ([string]$old.Os -ne [string]$cur.Os) { & $add ((U '\u041e\u0421: ')) ("$($old.Os) -> $($cur.Os)") }
    if ([math]::Abs([double]$old.RamGb - [double]$cur.RamGb) -ge 0.2) { & $add (U '\u041e\u0417\u0423: ') ("$($old.RamGb) -> $($cur.RamGb) " + (U '\u0413\u0411')) }
    $dFree = [double]$cur.SysFreeGb - [double]$old.SysFreeGb
    if ($old.SysFreeGb -and [math]::Abs($dFree) -ge [double](Cfg 'checks.changeFreeGb' 5)) { & $add (U '\u0421\u0432\u043e\u0431\u043e\u0434\u043d\u043e \u043d\u0430 \u0441\u0438\u0441\u0442\u0435\u043c\u043d\u043e\u043c \u0434\u0438\u0441\u043a\u0435: ') ("$($old.SysFreeGb) -> $($cur.SysFreeGb) " + (U '\u0413\u0411')) }
    foreach ($pair in @(@('Disks', (U '\u041d\u0430\u043a\u043e\u043f\u0438\u0442\u0435\u043b\u0438')), @('Av', (U '\u0410\u043d\u0442\u0438\u0432\u0438\u0440\u0443\u0441')))) {
        $o = @($old.($pair[0]) | Where-Object { $_ }); $n = @($cur.($pair[0]) | Where-Object { $_ })
        $plus = @($n | Where-Object { $o -notcontains $_ }); $minus = @($o | Where-Object { $n -notcontains $_ })
        if ($plus.Count)  { & $add ($pair[1] + (U ' \u2014 \u043d\u043e\u0432\u044b\u0435: ')) ($plus -join ', ') }
        if ($minus.Count) { & $add ($pair[1] + (U ' \u2014 \u043f\u0440\u043e\u043f\u0430\u043b\u0438: ')) ($minus -join ', ') }
    }
    $om = @{}; $on = @($old.SwN); $ov = @($old.SwV)
    for ($i = 0; $i -lt $on.Count; $i++) { $om[[string]$on[$i]] = [string]$ov[$i] }
    $nm = @{}; $cn = @($cur.SwN); $cv = @($cur.SwV)
    for ($i = 0; $i -lt $cn.Count; $i++) { $nm[[string]$cn[$i]] = [string]$cv[$i] }
    $new = @($nm.Keys | Where-Object { -not $om.ContainsKey($_) } | Sort-Object)
    $gone = @($om.Keys | Where-Object { -not $nm.ContainsKey($_) } | Sort-Object)
    $upd = @($nm.Keys | Where-Object { $om.ContainsKey($_) -and $om[$_] -ne $nm[$_] } | Sort-Object | ForEach-Object { "$_ ($($om[$_]) -> $($nm[$_]))" })
    if ($new.Count)  { & $add ((U '\u0423\u0441\u0442\u0430\u043d\u043e\u0432\u043b\u0435\u043d\u044b \u043f\u0440\u043e\u0433\u0440\u0430\u043c\u043c\u044b') + " ($($new.Count)): ") (Join-Limited $new) }
    if ($gone.Count) { & $add ((U '\u0423\u0434\u0430\u043b\u0435\u043d\u044b \u043f\u0440\u043e\u0433\u0440\u0430\u043c\u043c\u044b') + " ($($gone.Count)): ") (Join-Limited $gone) }
    if ($upd.Count)  { & $add ((U '\u041e\u0431\u043d\u043e\u0432\u043b\u0435\u043d\u044b \u043f\u0440\u043e\u0433\u0440\u0430\u043c\u043c\u044b') + " ($($upd.Count)): ") (Join-Limited $upd 25) }
    $head = '<p class="muted">' + (Enc ((U '\u0421\u0440\u0430\u0432\u043d\u0435\u043d\u0438\u0435 \u0441 \u043e\u0442\u0447\u0451\u0442\u043e\u043c \u043e\u0442 ') + [string]$old.Date)) + '</p>'
    if (-not $li.Count) { return $head + '<p>' + (Enc (U '\u0418\u0437\u043c\u0435\u043d\u0435\u043d\u0438\u0439 \u043d\u0435 \u043e\u0431\u043d\u0430\u0440\u0443\u0436\u0435\u043d\u043e.')) + '</p>' }
    $head + '<ul class="chg">' + ($li -join '') + '</ul>'
}

# ===================== EXCEL (OpenXML, no Excel needed) =====================
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$XNS  = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
$RNS  = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
$XSP  = 'http://www.w3.org/XML/1998/namespace'
$UTF8 = New-Object Text.UTF8Encoding($false)

function Col-Letter([int]$n) { $s = ''; while ($n -gt 0) { $m = ($n - 1) % 26; $s = ([string][char](65 + $m)) + $s; $n = [int][math]::Floor(($n - 1) / 26) }; $s }
function Col-Index([string]$l) { $n = 0; foreach ($ch in $l.ToCharArray()) { $n = $n * 26 + ([int][char]$ch - 64) }; $n }

function Read-ZipXml($zip, $name) {
    $e = $zip.GetEntry($name); if (-not $e) { return $null }
    $sr = New-Object IO.StreamReader($e.Open(), $UTF8)
    try { $d = New-Object Xml.XmlDocument; $d.PreserveWhitespace = $true; $d.LoadXml($sr.ReadToEnd()); $d } finally { $sr.Dispose() }
}
function Write-ZipText($zip, $name, [string]$text) {
    if ($zip.Mode -ne [IO.Compression.ZipArchiveMode]::Create) { $e = $zip.GetEntry($name); if ($e) { $e.Delete() } }
    $st = $zip.CreateEntry($name).Open()
    try { $b = $UTF8.GetBytes($text); $st.Write($b, 0, $b.Length) } finally { $st.Dispose() }
}
function Write-ZipXml($zip, $name, $doc) {
    Write-ZipText $zip $name ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + "`r`n" + $doc.DocumentElement.OuterXml)
}

function Get-SheetPath($zip) {
    $wb = Read-ZipXml $zip 'xl/workbook.xml'
    $ns = New-Object Xml.XmlNamespaceManager($wb.NameTable); $ns.AddNamespace('m', $XNS)
    $sh = $null; $want = Get-SheetNameRaw      # the configured sheet by name, otherwise the first one
    foreach ($s in @($wb.SelectNodes('//m:sheets/m:sheet', $ns))) { if (-not $sh) { $sh = $s }; if ($s.GetAttribute('name') -ieq $want) { $sh = $s; break } }
    $rid = $sh.GetAttribute('id', $RNS)
    $rels = Read-ZipXml $zip 'xl/_rels/workbook.xml.rels'
    foreach ($rel in $rels.DocumentElement.ChildNodes) {
        if ($rel.NodeType -eq 'Element' -and $rel.GetAttribute('Id') -eq $rid) {
            $t = $rel.GetAttribute('Target')
            if ($t.StartsWith('/')) { return $t.TrimStart('/') } else { return 'xl/' + $t }
        }
    }
    'xl/worksheets/sheet1.xml'
}

function Get-TextOf($node) {
    (@($node.GetElementsByTagName('t') | Where-Object { $_.ParentNode.LocalName -ne 'rPh' } | ForEach-Object { $_.InnerText }) -join '')
}
function Get-CellText($c, $sst) {
    $t = $c.GetAttribute('t')
    if ($t -eq 'inlineStr') { return (Get-TextOf $c) }
    $v = ''
    foreach ($ch in $c.ChildNodes) { if ($ch.LocalName -eq 'v') { $v = $ch.InnerText } }
    if ($t -eq 's' -and $v -ne '') { return $sst[[int]$v] }
    $v
}

function Set-Cell($doc, $row, [int]$colIdx, [string]$text, [string]$style, [bool]$numeric = $false) {
    $cell = $null; $before = $null
    foreach ($c in $row.ChildNodes) {
        if ($c.LocalName -ne 'c') { continue }
        $ci = Col-Index ([regex]::Match($c.GetAttribute('r'), '^[A-Z]+').Value)
        if ($ci -eq $colIdx) { $cell = $c; break }
        if ($ci -gt $colIdx) { $before = $c; break }
    }
    if (-not $cell) {
        $cell = $doc.CreateElement('c', $XNS)
        $cell.SetAttribute('r', (Col-Letter $colIdx) + $row.GetAttribute('r'))
        if ($style) { $cell.SetAttribute('s', $style) }
        if ($before) { [void]$row.InsertBefore($cell, $before) } else { [void]$row.AppendChild($cell) }
    }
    while ($cell.HasChildNodes) { [void]$cell.RemoveChild($cell.FirstChild) }
    [void]$cell.RemoveAttribute('t')
    if ($text -eq '') { return }
    if ($numeric) {
        $cell.SetAttribute('t', 'n')
        $v = $doc.CreateElement('v', $XNS); $v.InnerText = $text; [void]$cell.AppendChild($v)
    } else {
        $cell.SetAttribute('t', 'inlineStr')
        $is = $doc.CreateElement('is', $XNS); $t = $doc.CreateElement('t', $XNS); $t.InnerText = $text
        if ($text -ne $text.Trim()) { $t.SetAttribute('space', $XSP, 'preserve') }
        [void]$is.AppendChild($t); [void]$cell.AppendChild($is)
    }
}

function Get-SheetNameRaw {
    $n = [string](Cfg 'excel.sheetName' (U '\u0418\u043d\u0432\u0435\u043d\u0442\u0430\u0440\u0438\u0437\u0430\u0446\u0438\u044f'))
    $n = $n -replace '[\[\]:*?/\\]', '_'
    if ($n.Length -gt 31) { $n = $n.Substring(0, 31) }
    $n
}
function Get-SheetName { [Security.SecurityElement]::Escape((Get-SheetNameRaw)) }
function New-InventoryXlsx($path, [string[]]$headers) {
    $fs = [IO.File]::Open($path, 'Create', 'ReadWrite', 'None')
    $zip = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
    try {
        Write-ZipText $zip '[Content_Types].xml' ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>')
        Write-ZipText $zip '_rels/.rels' ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
        Write-ZipText $zip 'xl/workbook.xml' ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="' + $XNS + '" xmlns:r="' + $RNS + '"><sheets><sheet name="' + (Get-SheetName) + '" sheetId="1" r:id="rId1"/></sheets></workbook>')
        Write-ZipText $zip 'xl/_rels/workbook.xml.rels' ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>')
        Write-ZipText $zip 'xl/styles.xml' ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="' + $XNS + '"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFD9E1F2"/></patternFill></fill></fills><borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"/><right style="thin"/><top style="thin"/><bottom style="thin"/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center" wrapText="1"/></xf></cellXfs></styleSheet>')
        $cols = ''; $w = 12, 10, 13, 15, 24, 14, 14, 34, 36, 18, 22, 20, 26
        for ($i = 0; $i -lt $headers.Count; $i++) { $cols += '<col min="' + ($i + 1) + '" max="' + ($i + 1) + '" width="' + $w[$i] + '" customWidth="1"/>' }
        $h = ''
        for ($i = 0; $i -lt $headers.Count; $i++) { $h += '<c r="' + (Col-Letter ($i + 1)) + '1" s="1" t="inlineStr"><is><t>' + [Security.SecurityElement]::Escape($headers[$i]) + '</t></is></c>' }
        Write-ZipText $zip 'xl/worksheets/sheet1.xml' ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="' + $XNS + '"><dimension ref="A1:' + (Col-Letter $headers.Count) + '1"/><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight="15"/><cols>' + $cols + '</cols><sheetData><row r="1" ht="28" customHeight="1">' + $h + '</row></sheetData></worksheet>')
    } finally { $zip.Dispose(); $fs.Dispose() }
}

# ---- merge rules: never destroy manual data with a weaker detection ----
function Merge-Id($old, $new, $none) {
    $weak = @($none, $script:NoId)
    if ($new -and ($weak -notcontains $new)) { return $new }        # a real ID always wins
    if ($old -and ($weak -notcontains $old)) { return $old }        # a real or hand-typed value is never replaced by "none" / "ID not found"
    if ($new) { return $new }
    if ($old) { return $old }
    $none
}
function Get-DiskProtectionNames {       # product names known to the detector (built-in + config.json)
    $n = @($script:Sig.Disk.Keys) + 'Windows UWF'
    foreach ($d in @(Cfg 'diskProtectionDetect.disableBuiltin' @())) { $n = @($n | Where-Object { $_ -ne [string]$d }) }
    foreach ($xp in @(Cfg 'diskProtectionDetect.extraProducts' @())) { if ($xp.name) { $n += [string]$xp.name } }
    $n
}
function Merge-DiskProtection($old, $new, $none) {
    $names = @(Get-DiskProtectionNames | ForEach-Object { [regex]::Escape($_) })
    $prod = $(if ($names.Count) { '^(' + ($names -join '|') + ')' } else { '^(?!)' })
    if ($new -ne $none) {
        $p = [regex]::Match($new, $prod).Value
        if ($old -and $p -and $old.StartsWith($p)) { return $old }   # product is the same: keep the state a human wrote (the protected / unprotected state cannot be detected)
        return $new
    }
    if ($old -and $old -match ($prod + '|' + (U '\u0417\u0430\u0449\u0438\u0442\u0430'))) { return $none }   # software is gone
    if ($old) { return $old }                                                                                               # manual note 
    $none
}

# ---- hyperlink cell: =HYPERLINK("relative\path.html","label"), relative to the workbook folder (survives a changed drive letter) ----
function Add-LinkStyle($zip, [string]$baseIdx, [bool]$asLink = $true) {
    try {
        $sd = Read-ZipXml $zip 'xl/styles.xml'; if (-not $sd) { return '' }
        $sn = New-Object Xml.XmlNamespaceManager($sd.NameTable); $sn.AddNamespace('m', $XNS)
        $fonts = $sd.SelectSingleNode('//m:fonts', $sn); $fills = $sd.SelectSingleNode('//m:fills', $sn); $xfs = $sd.SelectSingleNode('//m:cellXfs', $sn)
        function El($n, $attrs) { $e = $sd.CreateElement($n, $XNS); foreach ($k in $attrs.Keys) { $e.SetAttribute($k, $attrs[$k]) }; $e }
        $pf = El 'patternFill' @{ patternType = 'solid' }
        [void]$pf.AppendChild((El 'fgColor' @{ rgb = 'FFE2EFDA' })); [void]$pf.AppendChild((El 'bgColor' @{ indexed = '64' }))
        $fill = El 'fill' @{}; [void]$fill.AppendChild($pf); [void]$fills.AppendChild($fill)
        $fln = @($fills.ChildNodes | Where-Object { $_.NodeType -eq 'Element' }).Count
        $fills.SetAttribute('count', [string]$fln)
        $xl = @($xfs.ChildNodes | Where-Object { $_.LocalName -eq 'xf' })
        $bi = 0; if ($baseIdx -ne '' -and [int]$baseIdx -lt $xl.Count) { $bi = [int]$baseIdx }
        $nx = $xl[$bi].CloneNode($true)
        $nx.SetAttribute('fillId', [string]($fln - 1)); $nx.SetAttribute('applyFill', '1')
        if ($asLink) {
            $font = El 'font' @{}
            [void]$font.AppendChild((El 'u' @{})); [void]$font.AppendChild((El 'sz' @{ val = '11' }))
            [void]$font.AppendChild((El 'color' @{ rgb = 'FF0563C1' })); [void]$font.AppendChild((El 'name' @{ val = 'Calibri' }))
            [void]$fonts.AppendChild($font)
            $fn = @($fonts.ChildNodes | Where-Object { $_.NodeType -eq 'Element' }).Count
            $fonts.SetAttribute('count', [string]$fn)
            $nx.SetAttribute('fontId', [string]($fn - 1)); $nx.SetAttribute('applyFont', '1')
        }
        [void]$xfs.AppendChild($nx)
        $xfs.SetAttribute('count', [string]($xl.Count + 1))
        Write-ZipXml $zip 'xl/styles.xml' $sd
        return [string]$xl.Count
    } catch { return '' }
}
function Get-LinkStyleOf($row, [int]$colIdx) {      # reuse the style of an existing link cell (do not grow styles.xml on every run)
    $ref = (Col-Letter $colIdx) + $row.GetAttribute('r')
    $c = $row.ChildNodes | Where-Object { $_.LocalName -eq 'c' -and $_.GetAttribute('r') -eq $ref } | Select-Object -First 1
    if ($c -and $c.GetAttribute('s') -and @($c.ChildNodes | Where-Object { $_.LocalName -eq 'f' }).Count) { return $c.GetAttribute('s') }
    ''
}
function Set-LinkCell($doc, $row, [int]$colIdx, [string]$rel, [string]$label, [string]$style) {
    Set-Cell $doc $row $colIdx $label $style
    $ref = (Col-Letter $colIdx) + $row.GetAttribute('r')
    $cell = $row.ChildNodes | Where-Object { $_.LocalName -eq 'c' -and $_.GetAttribute('r') -eq $ref } | Select-Object -First 1
    while ($cell.HasChildNodes) { [void]$cell.RemoveChild($cell.FirstChild) }
    $cell.SetAttribute('t', 'str')
    if ($style) { $cell.SetAttribute('s', $style) }
    $f = $doc.CreateElement('f', $XNS); $f.InnerText = 'HYPERLINK("' + $rel.Replace('"', '""') + '","' + $label.Replace('"', '""') + '")'
    $v = $doc.CreateElement('v', $XNS); $v.InnerText = $label
    [void]$cell.AppendChild($f); [void]$cell.AppendChild($v)
}

function Get-MergeRanges($doc, $ns) {
    $r = @()
    foreach ($m in @($doc.SelectNodes('//m:mergeCells/m:mergeCell', $ns))) {
        $x = [regex]::Match($m.GetAttribute('ref'), '^([A-Z]+)(\d+)(?::([A-Z]+)(\d+))?$')
        if (-not $x.Success -or -not $x.Groups[3].Success) { continue }
        $r += [pscustomobject]@{ C1 = (Col-Index $x.Groups[1].Value); R1 = [int]$x.Groups[2].Value; C2 = (Col-Index $x.Groups[3].Value); R2 = [int]$x.Groups[4].Value }
    }
    $r
}
function Find-MergeAt($merges, [int]$rn, [int]$col) {
    $merges | Where-Object { $_.R1 -le $rn -and $_.R2 -ge $rn -and $_.C1 -le $col -and $_.C2 -ge $col } | Select-Object -First 1
}

# writes one cell only when its text really changes; never erases with an empty value, never overwrites a formula,
# keeps a number a number (a manually typed floor "2" must not turn into text)
function Set-CellIf($doc, $row, [int]$col, [string]$old, [string]$new, [string]$style) {
    if ($col -le 0 -or $new -eq '' -or $old -ceq $new) { return $false }
    $ref = (Col-Letter $col) + $row.GetAttribute('r')
    $cell = $row.ChildNodes | Where-Object { $_.LocalName -eq 'c' -and $_.GetAttribute('r') -eq $ref } | Select-Object -First 1
    if ($cell -and @($cell.ChildNodes | Where-Object { $_.LocalName -eq 'f' }).Count) { Write-Log WARN "excel: $ref holds a formula, left as is"; return $false }
    $num = $false
    if ($cell -and $new -match '^\d{1,9}$' -and ($cell.GetAttribute('t') -eq '' -or $cell.GetAttribute('t') -eq 'n') -and $old -match '^\d+$') { $num = $true }
    Set-Cell $doc $row $col $new $style $num
    $true
}

# the worksheet part: copy, update, verify, then replace the original (a failure half-way never damages the workbook)
# self-check before the sheet is saved: any failure throws, the workbook is then NOT replaced (row goes to Service\pending_rows.csv)
function Test-InventoryDoc($zip, $doc, $ns, $data, $row, [int]$pcCol, [string]$pc) {
    if ($pcCol -le 0) { throw 'self-check: PC name column was not resolved' }
    $seen = @{}; $prev = 0
    foreach ($r in @($data.ChildNodes | Where-Object { $_.LocalName -eq 'row' })) {
        $rn = 0; if (-not [int]::TryParse($r.GetAttribute('r'), [ref]$rn) -or $rn -le $prev) { throw "self-check: row numbers are not unique / ascending (row '$($r.GetAttribute('r'))')" }
        $prev = $rn; $pc0 = 0
        foreach ($x in @($r.ChildNodes | Where-Object { $_.LocalName -eq 'c' })) {
            $m = [regex]::Match($x.GetAttribute('r'), '^([A-Z]+)(\d+)$')
            if (-not $m.Success -or [int]$m.Groups[2].Value -ne $rn) { throw "self-check: bad cell reference '$($x.GetAttribute('r'))' in row $rn" }
            $ci = Col-Index $m.Groups[1].Value
            if ($ci -le $pc0) { throw "self-check: cells out of order in row $rn" }
            $pc0 = $ci
        }
    }
    $cr = $row.ChildNodes | Where-Object { $_.LocalName -eq 'c' -and $_.GetAttribute('r') -eq ((Col-Letter $pcCol) + $row.GetAttribute('r')) } | Select-Object -First 1
    if (-not $cr -or (Get-TextOf $cr) -ne $pc) { throw 'self-check: the written row does not contain the PC name' }
    foreach ($cl in @($doc.SelectNodes('//m:cols/m:col', $ns))) {
        $mn = 0; $mx = 0
        if (-not [int]::TryParse($cl.GetAttribute('min'), [ref]$mn) -or -not [int]::TryParse($cl.GetAttribute('max'), [ref]$mx) -or $mn -lt 1 -or $mx -lt $mn) { throw 'self-check: a <col> element has no valid min/max' }
    }
    $sd = Read-ZipXml $zip 'xl/styles.xml'
    if ($sd) {
        $sn = New-Object Xml.XmlNamespaceManager($sd.NameTable); $sn.AddNamespace('m', $XNS)
        foreach ($pair in @(@('fonts', 'font'), @('fills', 'fill'), @('borders', 'border'), @('cellXfs', 'xf'))) {
            $nd = $sd.SelectSingleNode('//m:' + $pair[0], $sn)
            if ($nd -and [int]$nd.GetAttribute('count') -ne @($nd.ChildNodes | Where-Object { $_.LocalName -eq $pair[1] }).Count) { throw "self-check: styles.xml <$($pair[0])> count does not match its items" }
        }
        $nx = @($sd.SelectNodes('//m:cellXfs/m:xf', $sn)).Count
        foreach ($x in @($doc.SelectNodes('//m:c[@s]', $ns))) { if ([int]$x.GetAttribute('s') -ge $nx) { throw "self-check: cell $($x.GetAttribute('r')) uses a style that does not exist" } }
    }
}

# ---- colours of the state column: conditional formatting by the first words (red / yellow / green); added once, works for legacy wording too ----
function Add-StateFormatting($zip, $doc, $ns, [int]$stateCol, [int]$firstRow) {
    if ($stateCol -le 0) { return }
    try {
        $ws = $doc.DocumentElement
        $col = Col-Letter $stateCol
        $rules = @(
            @{ K = 'bad';  W = @('\u041e\u043f\u0430\u0441\u043d\u043e', '\u041f\u043b\u043e\u0445\u043e\u0435') },
            @{ K = 'warn'; W = @('\u0422\u0435\u0440\u043f\u0438\u043c\u043e', '\u0412\u043d\u0438\u043c\u0430\u043d\u0438\u0435') },
            @{ K = 'ok';   W = @('\u041d\u0435\u0442 \u043f\u0440\u043e\u0431\u043b\u0435\u043c', '\u0425\u043e\u0440\u043e\u0448\u0435\u0435') } )
        foreach ($cf0 in @($ws.SelectNodes('//m:conditionalFormatting', $ns))) {
            if (([string]$cf0.GetAttribute('sqref')).StartsWith($col) -and @($cf0.SelectNodes('m:cfRule[@text="' + (U '\u041e\u043f\u0430\u0441\u043d\u043e') + '"]', $ns)).Count) { return }     # already installed
        }
        $sd = Read-ZipXml $zip 'xl/styles.xml'; if (-not $sd) { return }
        $sn = New-Object Xml.XmlNamespaceManager($sd.NameTable); $sn.AddNamespace('m', $XNS)
        $dx = $sd.SelectSingleNode('//m:dxfs', $sn)
        if (-not $dx) {
            $anchor = $sd.SelectSingleNode('//m:cellStyles', $sn); if (-not $anchor) { $anchor = $sd.SelectSingleNode('//m:cellXfs', $sn) }
            if (-not $anchor) { return }
            $dx = $sd.CreateElement('dxfs', $XNS); $dx.SetAttribute('count', '0')
            [void]$sd.DocumentElement.InsertAfter($dx, $anchor)
        }
        $base = @($dx.ChildNodes | Where-Object { $_.NodeType -eq 'Element' }).Count
        $clr = @{ bad = @('FF9C0006', 'FFFFC7CE'); warn = @('FF9C5700', 'FFFFEB9C'); ok = @('FF006100', 'FFC6EFCE') }
        $ids = @{}; $n = 0
        foreach ($k in 'bad', 'warn', 'ok') {
            $d = $sd.CreateElement('dxf', $XNS)
            $f = $sd.CreateElement('font', $XNS); $c = $sd.CreateElement('color', $XNS); $c.SetAttribute('rgb', $clr[$k][0]); [void]$f.AppendChild($c); [void]$d.AppendChild($f)
            $fl = $sd.CreateElement('fill', $XNS); $pf = $sd.CreateElement('patternFill', $XNS); $bg = $sd.CreateElement('bgColor', $XNS); $bg.SetAttribute('rgb', $clr[$k][1])
            [void]$pf.AppendChild($bg); [void]$fl.AppendChild($pf); [void]$d.AppendChild($fl)
            [void]$dx.AppendChild($d); $ids[$k] = $base + $n; $n++
        }
        $dx.SetAttribute('count', [string]($base + 3))
        Write-ZipXml $zip 'xl/styles.xml' $sd

        $prio = 0
        foreach ($r0 in @($ws.SelectNodes('//m:cfRule', $ns))) { $p = 0; if ([int]::TryParse($r0.GetAttribute('priority'), [ref]$p) -and $p -gt $prio) { $prio = $p } }
        $cf = $doc.CreateElement('conditionalFormatting', $XNS)
        $cf.SetAttribute('sqref', ($col + $firstRow + ':' + $col + '1048576'))
        foreach ($rule in $rules) { foreach ($w0 in $rule.W) {
            $w = U $w0; $prio++
            $r = $doc.CreateElement('cfRule', $XNS)
            $r.SetAttribute('type', 'beginsWith'); $r.SetAttribute('dxfId', [string]$ids[$rule.K]); $r.SetAttribute('priority', [string]$prio)
            $r.SetAttribute('operator', 'beginsWith'); $r.SetAttribute('text', $w)
            $fo = $doc.CreateElement('formula', $XNS); $fo.InnerText = 'LEFT(' + $col + $firstRow + ',LEN("' + $w + '"))="' + $w + '"'
            [void]$r.AppendChild($fo); [void]$cf.AppendChild($r)
        } }
        $order = 'sheetData', 'sheetCalcPr', 'sheetProtection', 'protectedRanges', 'scenarios', 'autoFilter', 'sortState', 'dataConsolidate', 'customSheetViews', 'mergeCells', 'phoneticPr', 'conditionalFormatting'
        $last = $null
        foreach ($ch in $ws.ChildNodes) { if ($ch.NodeType -eq 'Element' -and ($order -contains $ch.LocalName)) { $last = $ch } }
        if ($last) { [void]$ws.InsertAfter($cf, $last) } else { [void]$ws.AppendChild($cf) }
    } catch { Write-Log WARN "excel: state colours were not added: $($_.Exception.Message)" }
}

function Write-InventoryRow($file, $headers, $builtin, $rec, $none, [bool]$created) {
    $keys = 'Num', 'Floor', 'Room', 'Place', 'User', 'RemoteA', 'RemoteB', 'State', 'Disk', 'Pc', 'Rpt', 'Serial', 'Model'
    $fs = [IO.File]::Open($file, 'Open', 'ReadWrite', 'None')
    $zip = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Update)
    try {
        $sp  = Get-SheetPath $zip
        $doc = Read-ZipXml $zip $sp
        if (-not $doc) { throw "worksheet '$sp' was not found in the workbook" }
        $ns = New-Object Xml.XmlNamespaceManager($doc.NameTable); $ns.AddNamespace('m', $XNS)
        $prot = $doc.SelectSingleNode('//m:sheetProtection', $ns)
        if ($prot -and $prot.GetAttribute('sheet') -match '^(1|true)$') { throw 'the sheet is protected (Excel: Review > Unprotect Sheet); the row was not written' }
        $merges = @(Get-MergeRanges $doc $ns)
        $sst = @(); $sd = Read-ZipXml $zip 'xl/sharedStrings.xml'
        if ($sd) { foreach ($si in $sd.DocumentElement.ChildNodes) { if ($si.LocalName -eq 'si') { $sst += (Get-TextOf $si) } } }
        $data = $doc.SelectSingleNode('//m:sheetData', $ns)
        $rows = @($data.ChildNodes | Where-Object { $_.LocalName -eq 'row' })

        # known header texts per field (config titles and built-in ones)
        $known = @{}; $all = @()
        for ($i = 0; $i -lt $keys.Count; $i++) {
            $known[$keys[$i]] = @(@($headers[$i], $builtin[$i]) | ForEach-Object { ([string]$_).Trim().ToLower() } | Select-Object -Unique)
            $all += $known[$keys[$i]]
        }
        # header row: normally row 1, but a few title rows above it are tolerated
        $hdrN = 1; $best = 0
        foreach ($r in ($rows | Where-Object { [int]$_.GetAttribute('r') -le 10 })) {
            $hit = 0
            foreach ($c in $r.ChildNodes) { if ($c.LocalName -eq 'c') { $tx = (Get-CellText $c $sst).Trim().ToLower(); if ($tx -and ($all -contains $tx)) { $hit++ } } }
            if ($hit -gt $best) { $best = $hit; $hdrN = [int]$r.GetAttribute('r') }
        }
        if ($best -lt 2) { $hdrN = 1 }
        $hdr = $rows | Where-Object { [int]$_.GetAttribute('r') -eq $hdrN } | Select-Object -First 1

        $hmap = @{}; $hText = @{}; $maxCol = 0; $lastHdrStyle = ''
        if ($hdr) {
            foreach ($c in $hdr.ChildNodes) {
                if ($c.LocalName -ne 'c') { continue }
                $ci = Col-Index ([regex]::Match($c.GetAttribute('r'), '^[A-Z]+').Value)
                if ($ci -gt $maxCol) { $maxCol = $ci }
                if ($c.GetAttribute('s')) { $lastHdrStyle = $c.GetAttribute('s') }
                $tx = (Get-CellText $c $sst).Trim()
                if ($tx) { $hText[$ci] = $tx; if (-not $hmap.ContainsKey($tx.ToLower())) { $hmap[$tx.ToLower()] = $ci } }
            }
        }
        # field -> column by header text, so inserted / reordered columns do not matter
        $Cm = @{}
        foreach ($k in $keys) { $Cm[$k] = 0; foreach ($t in $known[$k]) { if ($hmap.ContainsKey($t)) { $Cm[$k] = $hmap[$t]; break } } }
        for ($i = 0; $i -lt 9; $i++) {      # legacy position only into an EMPTY header cell; a column that holds anything else is never used
            $k = $keys[$i]
            if ($Cm[$k]) { continue }
            if (-not $hdr) { $Cm[$k] = $i + 1; continue }
            if (-not $hText.ContainsKey($i + 1)) { $Cm[$k] = $i + 1; Set-Cell $doc $hdr ($i + 1) $headers[$i] $lastHdrStyle; if ($i + 1 -gt $maxCol) { $maxCol = $i + 1 } }
            else { Write-Log WARN "excel: column '$($headers[$i])' is not in the header row (column $($i + 1) is '$($hText[$i + 1])'): this field is not written" }
        }
        $rptNew = $false
        if (-not $Cm.Pc) { $Cm.Pc = [math]::Max($maxCol + 1, 10); if ($hdr) { Set-Cell $doc $hdr $Cm.Pc $headers[9] $lastHdrStyle }; $maxCol = [math]::Max($maxCol, $Cm.Pc) }
        if (-not $Cm.Rpt) {
            $Cm.Rpt = [math]::Max($maxCol + 1, 11); $rptNew = $true
            if ($hdr) { $hs = Add-LinkStyle $zip $lastHdrStyle $false; Set-Cell $doc $hdr $Cm.Rpt $headers[10] $(if ($hs) { $hs } else { $lastHdrStyle }) }
        }

        foreach ($xk in 'Serial', 'Model') {       # identity columns are appended at the end when the sheet has none
            if ($Cm[$xk]) { continue }
            $xi = [array]::IndexOf($keys, $xk)
            $Cm[$xk] = [math]::Max($maxCol + 1, $xi + 1)
            if ($hdr) { Set-Cell $doc $hdr $Cm[$xk] $headers[$xi] $lastHdrStyle }
            $maxCol = [math]::Max($maxCol, $Cm[$xk])
        }

        # model of existing data rows
        $items = @()
        foreach ($r in $rows) {
            $rn = [int]$r.GetAttribute('r'); if ($rn -le $hdrN) { continue }
            $v = @{}
            foreach ($c in $r.ChildNodes) {
                if ($c.LocalName -ne 'c') { continue }
                $v[(Col-Index ([regex]::Match($c.GetAttribute('r'), '^[A-Z]+').Value))] = (Get-CellText $c $sst).Trim()
            }
            if (($v.Values | Where-Object { $_ }).Count -eq 0) { continue }
            $items += [pscustomobject]@{ Node = $r; N = $rn; V = $v }
        }
        function Cv($it, $i) { if ($i -gt 0 -and $it.V.ContainsKey($i)) { $it.V[$i] } else { '' } }
        $same = { param($a, $b) $a -and $b -and ($a.Trim() -ieq $b.Trim()) }

        # find existing row: PC name > remote access ID > floor+room+place > user (only if unique and has no PC name yet)
        $hit = $null; $how = ''
        $hit = $items | Where-Object { & $same (Cv $_ $Cm.Pc) $rec.Pc } | Select-Object -First 1; if ($hit) { $how = 'PC name' }
        if ($hit -and $Cm.Serial -and $rec.Serial) {        # same PC name, but another serial number: probably a different computer
            $sc = Cv $hit $Cm.Serial
            if ($sc -and -not (& $same $sc $rec.Serial)) { Write-Log WARN "excel: row $($hit.N) has the same PC name, but another serial number ($sc / $($rec.Serial)): treated as a different PC"; $hit = $null; $how = '' }
        }
        if (-not $hit -and $Cm.Serial -and $rec.Serial) { $hit = $items | Where-Object { & $same (Cv $_ $Cm.Serial) $rec.Serial } | Select-Object -First 1; if ($hit) { $how = 'serial number' } }
        if (-not $hit -and $Cm.RemoteA -and $rec.RemoteA -ne $none -and $rec.RemoteA -ne $script:NoId) { $hit = $items | Where-Object { (Cv $_ $Cm.RemoteA) -eq $rec.RemoteA } | Select-Object -First 1; if ($hit) { $how = 'remote access ID' } }
        if (-not $hit -and $Cm.Floor -and $Cm.Room -and $Cm.Place -and $rec.Floor -and $rec.Room -and $rec.Place) {
            $hit = $items | Where-Object { (& $same (Cv $_ $Cm.Floor) $rec.Floor) -and (& $same (Cv $_ $Cm.Room) $rec.Room) -and (& $same (Cv $_ $Cm.Place) $rec.Place) } | Select-Object -First 1
            if ($hit) { $how = 'floor/room/place' }
        }
        if (-not $hit -and $Cm.User -and $rec.User) {
            $cand = @($items | Where-Object { (& $same (Cv $_ $Cm.User) $rec.User) -and -not (Cv $_ $Cm.Pc) })
            if ($cand.Count -eq 1) { $hit = $cand[0]; $how = 'user' }
        }
        $lastRow = ($rows | ForEach-Object { [int]$_.GetAttribute('r') } | Measure-Object -Maximum).Maximum
        if (-not $lastRow) { $lastRow = $hdrN }
        foreach ($m in $merges) { if ($m.R2 -gt $lastRow) { $lastRow = $m.R2 } }       # never write into (or under) a merged block

        $writeCols = @($Cm.Values | Where-Object { $_ })
        if ($hit) {
            $row = $hit.Node
            foreach ($cc in $writeCols) { $mg = Find-MergeAt $merges $hit.N $cc; if ($mg) { throw "cell $(Col-Letter $cc)$($hit.N) is inside a merged range; the row was not written (unmerge the cells)" } }
            $st = @{}; foreach ($c in $row.ChildNodes) { if ($c.LocalName -eq 'c') { $st[(Col-Index ([regex]::Match($c.GetAttribute('r'), '^[A-Z]+').Value))] = $c.GetAttribute('s') } }
            $sty = { param($i) if ($st.ContainsKey($i)) { $st[$i] } elseif ($st.Count) { ($st.Values | Select-Object -First 1) } else { '' } }
            $n = @{}
            $n.Floor = if ($rec.Floor) { $rec.Floor } else { Cv $hit $Cm.Floor }
            $n.Room  = if ($rec.Room)  { $rec.Room }  else { Cv $hit $Cm.Room }
            $n.Place = if ($rec.Place) { $rec.Place } else { Cv $hit $Cm.Place }
            $n.User  = if ($rec.UserFromPassport -or -not (Cv $hit $Cm.User)) { $rec.User } else { Cv $hit $Cm.User }
            $n.RemoteA   = Merge-Id (Cv $hit $Cm.RemoteA) $rec.RemoteA $none
            $n.RemoteB   = Merge-Id (Cv $hit $Cm.RemoteB) $rec.RemoteB $none
            $cur = Cv $hit $Cm.State
            $n.State = if ($rec.State -and (Test-AutoState $cur)) { $rec.State } elseif ($cur) { $cur } else { Get-DefaultState }
            $n.Serial = if ($rec.Serial) { $rec.Serial } else { Cv $hit $Cm.Serial }
            $n.Model  = if ($rec.Model)  { $rec.Model }  else { Cv $hit $Cm.Model }
            $n.Disk = Merge-DiskProtection (Cv $hit $Cm.Disk) $rec.Disk $none
            $n.Pc    = $rec.Pc
            $changed = 0
            foreach ($k in 'Floor', 'Room', 'Place', 'User', 'RemoteA', 'RemoteB', 'State', 'Disk', 'Pc', 'Serial', 'Model') {
                if (Set-CellIf $doc $row $Cm[$k] (Cv $hit $Cm[$k]) ([string]$n[$k]) (& $sty $Cm[$k])) { $changed++ }
            }
            [void]$row.RemoveAttribute('spans')
            if ($rec.ReportRel -and $Cm.Rpt) { $ls = Get-LinkStyleOf $row $Cm.Rpt; if (-not $ls) { $ls = Add-LinkStyle $zip (& $sty $Cm.Pc) $true }; Set-LinkCell $doc $row $Cm.Rpt $rec.ReportRel $rec.ReportLabel $ls }
            $result = "updated row $($hit.N) (match: $how; cells changed: $changed)"
            $last = $lastRow
        } else {
            $new = $lastRow + 1
            foreach ($cc in $writeCols) { $mg = Find-MergeAt $merges $new $cc; if ($mg) { throw "the new row $new would fall into a merged range; the row was not written" } }
            $num = ($items | ForEach-Object { $x = 0; if ([int]::TryParse((Cv $_ $Cm.Num), [ref]$x)) { $x } else { 0 } } | Measure-Object -Maximum).Maximum
            $src = $items | Where-Object { $_.N -eq $lastRow } | Select-Object -First 1; if (-not $src) { $src = $items | Select-Object -Last 1 }
            $st = @{}; if ($src) { foreach ($c in $src.Node.ChildNodes) { if ($c.LocalName -eq 'c') { $st[(Col-Index ([regex]::Match($c.GetAttribute('r'), '^[A-Z]+').Value))] = $c.GetAttribute('s') } } }
            $sty = { param($i) if ($st.ContainsKey($i)) { $st[$i] } elseif ($created) { '2' } else { '' } }
            $row = $doc.CreateElement('row', $XNS); $row.SetAttribute('r', [string]$new); [void]$data.AppendChild($row)
            if ($Cm.Num) { Set-Cell $doc $row $Cm.Num ([string]([int]$num + 1)) (& $sty $Cm.Num) $true }
            $vals = @{ Floor = $rec.Floor; Room = $rec.Room; Place = $rec.Place; User = $rec.User; RemoteA = $rec.RemoteA; RemoteB = $rec.RemoteB; State = $(if ($rec.State) { $rec.State } else { Get-DefaultState }); Disk = $rec.Disk; Pc = $rec.Pc; Serial = $rec.Serial; Model = $rec.Model }
            foreach ($k in $vals.Keys) { if ($Cm[$k]) { Set-Cell $doc $row $Cm[$k] ([string]$vals[$k]) (& $sty $Cm[$k]) } }
            if ($rec.ReportRel -and $Cm.Rpt) { $ls = Get-LinkStyleOf $row $Cm.Rpt; if (-not $ls) { $ls = Add-LinkStyle $zip (& $sty $Cm.Pc) $true }; Set-LinkCell $doc $row $Cm.Rpt $rec.ReportRel $rec.ReportLabel $ls }
            $last = $new
            $result = "added row $new (#$([int]$num + 1))"
        }

        # new report column: paint the empty cells of existing rows too, so the whole column has its own colour
        if ($rptNew) {
            $fsty = Add-LinkStyle $zip (& $sty $Cm.Pc) $false
            foreach ($rw in @($data.ChildNodes | Where-Object { $_.LocalName -eq 'row' })) {
                $rn = [int]$rw.GetAttribute('r'); if ($rn -le $hdrN) { continue }
                if (Find-MergeAt $merges $rn $Cm.Rpt) { continue }
                $ref = (Col-Letter $Cm.Rpt) + $rn
                $has = $rw.ChildNodes | Where-Object { $_.LocalName -eq 'c' -and $_.GetAttribute('r') -eq $ref } | Select-Object -First 1
                if (-not $has -and $fsty) { Set-Cell $doc $rw $Cm.Rpt '' $fsty; [void]$rw.RemoveAttribute('spans') }
            }
        }

        # dimension / autofilter (its own start cell is kept) / column width
        $lastCol = [math]::Max($maxCol, [math]::Max($Cm.Pc, $Cm.Rpt))
        $dim = $doc.SelectSingleNode('//m:dimension', $ns)
        if ($dim) { $dim.SetAttribute('ref', 'A1:' + (Col-Letter $lastCol) + [math]::Max($last, $lastRow)) }
        $af = $doc.SelectSingleNode('//m:autoFilter', $ns)
        if ($af -and $af.GetAttribute('ref')) {
            $a0 = [regex]::Match($af.GetAttribute('ref'), '^[A-Z]+\d+').Value; if (-not $a0) { $a0 = 'A' + $hdrN }
            $af.SetAttribute('ref', $a0 + ':' + (Col-Letter $lastCol) + [math]::Max($last, $lastRow))
        }
        $colsN = $doc.SelectSingleNode('//m:cols', $ns)
        foreach ($cc in @($Cm.Pc, $Cm.Rpt)) {
            if ($colsN -and -not ($colsN.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and [int]$_.GetAttribute('min') -le $cc -and [int]$_.GetAttribute('max') -ge $cc })) {
                $cn = $doc.CreateElement('col', $XNS); $cn.SetAttribute('min', [string]$cc); $cn.SetAttribute('max', [string]$cc)
                $cn.SetAttribute('width', $(if ($cc -eq $Cm.Rpt) { '22' } else { '18' })); $cn.SetAttribute('customWidth', '1'); [void]$colsN.AppendChild($cn)
            }
        }
        Add-StateFormatting $zip $doc $ns ([int]$Cm.State) ($hdrN + 1)
        Test-InventoryDoc $zip $doc $ns $data $row $Cm.Pc ([string]$rec.Pc)
        Write-ZipXml $zip $sp $doc
    } finally { $zip.Dispose(); $fs.Dispose() }
    $result
}

function Update-InventoryXlsx($path, $rec, $none) {
    $builtin = @('#', '\u042d\u0442\u0430\u0436', '\u041f\u043e\u043c\u0435\u0449\u0435\u043d\u0438\u0435', '\u0420\u0430\u0431\u043e\u0447\u0435\u0435 \u043c\u0435\u0441\u0442\u043e', '\u041f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u0435\u043b\u044c', '\u0423\u0434\u0430\u043b\u0451\u043d\u043d\u044b\u0439 \u0434\u043e\u0441\u0442\u0443\u043f 1 (ID)', '\u0423\u0434\u0430\u043b\u0451\u043d\u043d\u044b\u0439 \u0434\u043e\u0441\u0442\u0443\u043f 2 (ID)', '\u0421\u043e\u0441\u0442\u043e\u044f\u043d\u0438\u0435 \u0440\u0430\u0431\u043e\u0447\u0435\u0439 \u0441\u0442\u0430\u043d\u0446\u0438\u0438', '\u0417\u0430\u0449\u0438\u0442\u0430 \u0434\u0438\u0441\u043a\u0430', '\u0418\u043c\u044f \u041f\u041a', '\u041e\u0442\u0447\u0451\u0442', '\u0421\u0435\u0440\u0438\u0439\u043d\u044b\u0439 \u043d\u043e\u043c\u0435\u0440', '\u041c\u043e\u0434\u0435\u043b\u044c') | ForEach-Object { U $_ }
    $headers = @($builtin)
    $hc = @(Cfg 'excel.headers' @())      # config.json: custom column titles (used when a NEW workbook is created; existing sheets are matched by header text)
    if ($hc.Count -eq 11) { $hc = @($hc) + @($headers[11..12]) }      # configs made before 1.3.0 have no identity columns
    if ($hc.Count -eq $headers.Count) { $headers = @($hc | ForEach-Object { [string]$_ }) }
    elseif ($hc.Count) { Write-Host "  excel.headers must contain $($headers.Count) items, built-in headers are used" -ForegroundColor Yellow }

    if (-not (Test-Path -LiteralPath $path)) {
        New-InventoryXlsx $path $headers
        $rr = @(Write-InventoryRow $path $headers $builtin $rec $none $true)
        return ('created file; ' + [string]$rr[-1])
    }
    $probe = [IO.File]::Open($path, 'Open', 'ReadWrite', 'None'); $probe.Dispose()      # throws if the file is open in Excel
    $bk = Join-Path $SvcDir 'backup'
    New-Item -ItemType Directory -Force $bk | Out-Null
    Copy-Item -LiteralPath $path (Join-Path $bk ([IO.Path]::GetFileNameWithoutExtension($path) + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.xlsx')) -Force
    Get-ChildItem $bk -Filter '*.xlsx' | Sort-Object LastWriteTime -Descending | Select-Object -Skip ([int](Cfg 'backup.keep' 10)) | Remove-Item -Force -ErrorAction SilentlyContinue
    $tmp = $path + '.tmp'
    try {
        Copy-Item -LiteralPath $path -Destination $tmp -Force
        $rr = @(Write-InventoryRow $tmp $headers $builtin $rec $none $false); $result = [string]$rr[-1]
        $vz = [IO.Compression.ZipFile]::OpenRead($tmp)       # the updated copy must open and parse before it replaces the original
        try { [void](Read-ZipXml $vz (Get-SheetPath $vz)) } finally { $vz.Dispose() }
        [IO.File]::Copy($tmp, $path, $true)
    } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } }
    $result
}

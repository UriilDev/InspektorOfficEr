# ===================== PC PASSPORT =====================
# ---- passport: C:\ -> script folder (USB) -> desktops (current user, all users, Public, OneDrive) ----
function Get-DesktopDirs {
    $r = @()
    try { $r += [Environment]::GetFolderPath('Desktop') } catch { }
    if ($env:USERPROFILE) { $r += Join-Path $env:USERPROFILE 'Desktop' }
    foreach ($d in @(Get-ChildItem 'C:\Users' -Directory -Force -ErrorAction SilentlyContinue)) {
        $r += Join-Path $d.FullName 'Desktop'
        foreach ($o in @(Get-ChildItem $d.FullName -Directory -Filter 'OneDrive*' -Force -ErrorAction SilentlyContinue)) { $r += Join-Path $o.FullName 'Desktop' }
    }
    $r += 'C:\Users\Public\Desktop'
    $r | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
}

function Read-PassportFile($path) {
    $al = @{
        Floor = @((U '\u042d\u0442\u0430\u0436'), 'Floor')
        Room  = @((U '\u041a\u0430\u0431\u0438\u043d\u0435\u0442'), (U '\u041f\u043e\u043c\u0435\u0449\u0435\u043d\u0438\u0435'), 'Room')
        Place = @((U '\u041c\u0435\u0441\u0442\u043e'), (U '\u0420\u0430\u0431\u043e\u0447\u0435\u0435 \u043c\u0435\u0441\u0442\u043e'), 'Place')
        User  = @((U '\u041f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u0435\u043b\u044c'), 'User')
    }
    $v = @{ Floor = ''; Room = ''; Place = ''; User = '' }
    $t = (Read-TextSmart $path).Trim()
    if ($t.StartsWith('{')) {
        $o = $t | ConvertFrom-Json
        foreach ($prop in $o.PSObject.Properties) {
            foreach ($f in @($al.Keys)) { if ($al[$f] -contains $prop.Name.Trim() -and $null -ne $prop.Value) { $v[$f] = ([string]$prop.Value).Trim() } }
        }
    } else {
        foreach ($line in ($t -split "`r?`n")) {
            $m = [regex]::Match($line, '^\s*([^:=]+?)\s*[:=]\s*(.*?)\s*$')
            if (-not $m.Success) { continue }
            foreach ($f in @($al.Keys)) { if ($al[$f] -contains $m.Groups[1].Value) { $v[$f] = $m.Groups[2].Value } }
        }
    }
    if (@($v.Values | Where-Object { $_ }).Count) { return $v }
    $null
}

# ---- no passport found: ask once, save on the USB drive (survives Deep Freeze / Shadow Defender reboots) ----
function Ask-Passport {
    $maxRoom = @{}
    $cr = Cfg 'passport.roomsPerFloor' $null
    if ($cr) { foreach ($pr in $cr.PSObject.Properties) { $maxRoom[[string]$pr.Name] = [int]$pr.Value } }
    if (-not $maxRoom.Count) { $maxRoom = @{ '1' = 10; '2' = 10 } }     # default: rooms per floor
    Write-Host ''
    Write-Host ('  ' + (U '\u041f\u0430\u0441\u043f\u043e\u0440\u0442 \u041f\u041a \u043d\u0435 \u043d\u0430\u0439\u0434\u0435\u043d. \u0423\u043a\u0430\u0436\u0438\u0442\u0435 \u0440\u0430\u0441\u043f\u043e\u043b\u043e\u0436\u0435\u043d\u0438\u0435 \u043f\u043e \u043f\u043b\u0430\u043d\u0443 \u0437\u0434\u0430\u043d\u0438\u044f (Enter - \u043f\u0440\u043e\u043f\u0443\u0441\u0442\u0438\u0442\u044c).')) -ForegroundColor Yellow
    $x = 0
    while ($true) {
        $fl = (Read-Host ('  ' + ((U '\u042d\u0442\u0430\u0436') + ' (' + (($maxRoom.Keys | Sort-Object) -join ' / ') + ')'))).Trim()
        if ($fl -eq '') { return $null }
        if ($maxRoom.ContainsKey($fl)) { break }
    }
    while ($true) {
        $rm = (Read-Host ('  ' + ((U '\u041f\u043e\u043c\u0435\u0449\u0435\u043d\u0438\u0435 (\u043d\u043e\u043c\u0435\u0440 \u043f\u043e \u043f\u043b\u0430\u043d\u0443, 1-{0})') -f $maxRoom[$fl]))).Trim()
        if ($rm -eq '') { return $null }
        if ([int]::TryParse($rm, [ref]$x) -and $x -ge 1 -and $x -le $maxRoom[$fl]) { $rm = [string]$x; break }
    }
    while ($true) {
        $pl = (Read-Host ('  ' + (U '\u0420\u0430\u0431\u043e\u0447\u0435\u0435 \u043c\u0435\u0441\u0442\u043e (\u043d\u043e\u043c\u0435\u0440 \u0432 \u043f\u043e\u043c\u0435\u0449\u0435\u043d\u0438\u0438)'))).Trim()
        if ($pl -eq '') { return $null }
        if ([int]::TryParse($pl, [ref]$x) -and $x -ge 1) { $pl = [string]$x; break }
    }
    $us = (Read-Host ('  ' + (U '\u041f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u0435\u043b\u044c (Enter - \u043d\u0435 \u043c\u0435\u043d\u044f\u0442\u044c)'))).Trim()
    $r = @{ Floor = $fl; Room = $rm; Place = $pl; User = $us; Source = (U '\u0432\u0432\u0435\u0434\u0435\u043d\u043e \u0432\u0440\u0443\u0447\u043d\u0443\u044e') }
    try {
        $o = [ordered]@{}
        $o[(U '\u042d\u0442\u0430\u0436')] = $fl; $o[(U '\u041f\u043e\u043c\u0435\u0449\u0435\u043d\u0438\u0435')] = $rm; $o[(U '\u0420\u0430\u0431\u043e\u0447\u0435\u0435 \u043c\u0435\u0441\u0442\u043e')] = $pl; $o[(U '\u041f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u0435\u043b\u044c')] = $us
        New-Item -ItemType Directory -Force $PassDir | Out-Null; $f = Join-Path $PassDir ('pc_info_' + $env:COMPUTERNAME + '.json')
        [IO.File]::WriteAllText($f, ($o | ConvertTo-Json), (New-Object Text.UTF8Encoding($true)))
        $r.Source = $f + (U ' (\u0441\u043e\u0445\u0440\u0430\u043d\u0435\u043d\u043e)')
    } catch { Write-Host "  cannot save passport: $($_.Exception.Message)" -ForegroundColor Yellow }
    $r
}

function Get-PcPassport {
    $p = [ordered]@{ Floor = ''; Room = ''; Place = ''; User = ''; Source = '' }
    $names = @("pc_info_$env:COMPUTERNAME.json", "pc_info_$env:COMPUTERNAME.txt", 'pc_info.json', 'pc_info.txt', 'pc_info.json.txt', 'pc_info.txt.txt')
    $locs  = (@($PassDir, 'C:\', $Root) + @(Get-DesktopDirs)) | Where-Object { $_ } | Select-Object -Unique
    foreach ($loc in $locs) {
        foreach ($n in $names) {
            $f = Join-Path $loc $n
            if (-not (Test-Path $f -PathType Leaf)) { continue }
            try {
                $v = Read-PassportFile $f
                if ($v) { foreach ($k in 'Floor', 'Room', 'Place', 'User') { $p[$k] = $v[$k] }; $p.Source = $f; break }
                Write-Host "  passport file has no known fields, skipped: $f" -ForegroundColor Yellow
            } catch { Write-Host "  passport file unreadable ($f): $($_.Exception.Message)" -ForegroundColor Yellow }
        }
        if ($p.Source) { break }
    }
    if (-not $p.Source -and -not $NoPrompt -and [Environment]::UserInteractive) {
        $a = Ask-Passport
        if ($a) { foreach ($k in 'Floor', 'Room', 'Place', 'User') { $p[$k] = $a[$k] }; $p.Source = $a.Source }
    }
    $p.UserFromPassport = [bool]$p.User
    if (-not $p.User) { $p.User = $env:USERNAME }
    $p.Pc = $env:COMPUTERNAME
    $p
}

# ===================== INVENTORY -> EXCEL =====================
function Find-XlsxPath {
    $custom = Cfg 'paths.workbook' $null
    if ($custom) { return (RootPath ([string]$custom)) }
    $name = (U '\u0417\u0430\u043c\u043e\u0440\u043e\u0437\u043a\u0430') + '.xlsx'
    $p = Join-Path $Root $name
    if (Test-Path $p) { return $p }
    $f = Get-ChildItem $Root -Filter ((U '\u0417\u0430\u043c\u043e\u0440\u043e\u0437\u043a\u0430') + '*.xlsx') -File -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -notlike '~$*' } | Select-Object -First 1
    if ($f) { return $f.FullName }
    $p
}

function Save-PendingRow($rec) {
    $f = Join-Path $OutDir '_pending_rows.csv'
    $isNew = -not (Test-Path $f)
    $esc = { param($s) '"' + ([string]$s).Replace('"', '""') + '"' }
    $line = (@($rec.Floor, $rec.Room, $rec.Place, $rec.User, $rec.AnyDesk, $rec.Hop, $rec.State, $rec.Freeze, $rec.Pc, (Get-Date -Format 'yyyy-MM-dd HH:mm')) | ForEach-Object { & $esc $_ }) -join ';'
    $txt = ''
    if ($isNew) { $txt = '"Floor";"Room";"Place";"User";"AnyDesk";"HopToDesk";"State";"Freeze";"PC";"Collected"' + "`r`n" }
    [IO.File]::AppendAllText($f, $txt + $line + "`r`n", (New-Object Text.UTF8Encoding($true)))
    $f
}

# returns 0 ok, 5 Excel not updated
function Invoke-Inventory {
    Write-Host '--- inventory ---'
    $pp  = Get-PcPassport
    $rec = [pscustomobject]@{
        Floor = $pp.Floor; Room = $pp.Room; Place = $pp.Place; User = $pp.User; UserFromPassport = $pp.UserFromPassport
        AnyDesk = $(if (Cfg 'features.anyDesk' $true) { Tm 'AnyDesk' { Get-AnyDeskId } } else { $NO }); Hop = $(if (Cfg 'features.hopToDesk' $true) { Tm 'HopToDesk' { Get-HopToDeskId } } else { $NO }); State = [string](Cfg 'excel.defaultState' (U '\u0425\u043e\u0440\u043e\u0448\u0435\u0435'))
        Freeze = $(if (Cfg 'features.freezeDetect' $true) { Tm 'Freeze' { Get-FreezeStatus } } else { $NO }); Pc = $env:COMPUTERNAME; ReportRel = ''; ReportLabel = ''
    }
    function Via($x) { if ($x) { "<- $x" } else { '<- not found' } }
    Write-Host "  passport  : $(if ($pp.Source) { $pp.Source } else { 'not found (C:\, USB root, desktops), using Windows user name' })"
    Write-Host "  PC / user : $($rec.Pc) / $($rec.User)"
    Write-Host "  floor/room/place : $($rec.Floor) / $($rec.Room) / $($rec.Place)"
    Write-Host "  AnyDesk   : $($rec.AnyDesk)  $(Via $script:Src.AnyDesk)"
    Write-Host "  HopToDesk : $($rec.Hop)  $(Via $script:Src.Hop)"
    Write-Host "  Freeze    : $($rec.Freeze)  $(Via $script:Src.Freeze)"

    $xl = Find-XlsxPath
    foreach ($c in @($Out)) {
        if ((Test-Path $c) -and ((Get-Item $c).Length -gt 0)) {
            $base = (Split-Path $xl).TrimEnd('\') + '\'
            $rec.ReportRel   = $(if ($c.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { $c.Substring($base.Length) } else { $c })
            $rec.ReportLabel = ([string](Cfg 'excel.reportLabel' (U '\u041e\u0442\u0447\u0451\u0442'))) + ' ' + (Get-Date -Format ([string](Cfg 'excel.labelDateFormat' 'yyyy-MM-dd')))
            Write-Host "  report link: $($rec.ReportRel)"
            break
        }
    }
    try { $rec | ConvertTo-Json | Out-File (Join-Path $OutDir '_last_inventory.json') -Encoding utf8 } catch { }      # after the report link is known
    try {
        $res = Update-InventoryXlsx $xl $rec $NO
        Write-Host "  Excel     : $res  [$xl]" -ForegroundColor Green
        return 0
    } catch {
        Write-Host "  Excel NOT updated: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Message -match 'protected|merged') { Write-Host '  (fix the table as described above and run again; nothing was changed in the workbook)' -ForegroundColor Yellow }
        else { Write-Host '  (if the file is open in Excel - close it and run again; the workbook was not changed)' -ForegroundColor Yellow }
        $pf = Save-PendingRow $rec
        Write-Host "  row saved to: $pf" -ForegroundColor Yellow
        return 5
    }
}

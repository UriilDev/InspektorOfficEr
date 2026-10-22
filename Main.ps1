# ======================= MAIN =======================
New-Item -ItemType Directory -Force $OutDir | Out-Null
try { Start-Transcript -Path (Join-Path $OutDir '_last_run.log') -Force | Out-Null } catch { }
Write-Host "$AppName v$AppVer" -ForegroundColor Cyan

$invRc = 0; $rptRc = 0; $t0all = Get-Date
if (-not $SkipReport) {            # report first: its file name goes into the Excel row as a link
    try { New-InspectorReport $Out; Write-Host "Report    : $Out" -ForegroundColor Green }
    catch { Write-Host "Report failed: $($_.Exception.Message)" -ForegroundColor Red; $rptRc = 3 }
}
if (-not $SkipExcel) {
    try { $invRc = Invoke-Inventory } catch { Write-Host "Inventory error: $($_.Exception.Message)" -ForegroundColor Red; $invRc = 5 }
}

Write-Host ''
Write-Host "Result: report=$rptRc, inventory=$invRc, total $([int]((Get-Date) - $t0all).TotalSeconds)s"
if ($invRc -eq 5) { Write-Host "Excel was NOT updated. Close the .xlsx file and run again. Row saved to: $(Join-Path $OutDir '_pending_rows.csv')" -ForegroundColor Yellow }
if ($rptRc -eq 0 -and $invRc -eq 0) {
    if ((Cfg 'ui.openReportWhenDone' $true) -and -not $SkipReport -and (Test-Path $Out)) { try { Start-Process $Out } catch { } }
    elseif (Cfg 'ui.openFolderWhenDone' $true) { try { Start-Process explorer.exe -ArgumentList ('"' + $OutDir + '"') } catch { } }
}
if ($rptRc -ne 0) { Finish $rptRc }
if ($invRc -ne 0) { Finish $invRc }
Finish 0

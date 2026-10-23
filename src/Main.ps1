# ======================= MAIN =======================
New-Item -ItemType Directory -Force $OutDir | Out-Null
Move-LegacyServiceFiles
New-Item -ItemType Directory -Force $SvcDir | Out-Null
try { Start-Transcript -Path (Join-Path $SvcDir 'last_run.log') -Force | Out-Null } catch { }
Write-Host "$AppName v$AppVer" -ForegroundColor Cyan
if (-not (Test-IsAdmin)) { Write-Log WARN 'Not running as Administrator: service profiles, some WMI classes and disk details may be unavailable. Use Inspektor.bat (it asks for elevation).' }
if ($Diagnose) { Write-Log INFO 'Diagnose mode: collecting a detailed log' }

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
if ($Diagnose) { try { Write-Host "Diagnose  : $(Save-DiagnoseLog $SvcDir)" -ForegroundColor Cyan } catch { Write-Host "Diagnose log failed: $($_.Exception.Message)" -ForegroundColor Red } }
if ($invRc -eq 5) { Write-Host "Excel was NOT updated. Close the .xlsx file and run again. Row saved to: $(Join-Path $SvcDir 'pending_rows.csv')" -ForegroundColor Yellow }
if ($rptRc -eq 0 -and $invRc -eq 0) {
    if ((Cfg 'ui.openReportWhenDone' $true) -and -not $SkipReport -and (Test-Path $Out)) { try { Open-InBrowser $Out } catch { } }
    elseif (Cfg 'ui.openFolderWhenDone' $true) { try { Start-Process explorer.exe -ArgumentList ('"' + $OutDir + '"') } catch { } }
}
if ($rptRc -ne 0) { Finish $rptRc }
if ($invRc -ne 0) { Finish $invRc }
Finish 0

# ===================== CONTEXT: config, switches, paths (runs once at startup) =====================
$Root = $PSScriptRoot
$Cfg  = Import-InspektorConfig (Join-Path $Root 'config.json')

# command-line parameters always win over config.json
if (-not (Cfg 'features.hardwareCollector' $true)) { $SkipReport = [switch]$true }
if (-not (Cfg 'features.excel' $true))        { $SkipExcel = [switch]$true }
if (-not (Cfg 'features.remoteAccessCli' $true)) { $NoRemoteCli  = [switch]$true }
if (-not (Cfg 'passport.askIfMissing' $true)) { $NoPrompt  = [switch]$true }

# -Diagnose collects the full debug log (also keeps the console verbose)
# paths (drive letter is detected from the script location)
$Drive   = Split-Path -Qualifier $Root
$OutDir  = RootPath ([string](Cfg 'paths.reportsDir' 'Raports'))
$SvcDir  = RootPath ([string](Cfg 'paths.serviceDir' 'Service'))      # service files (state snapshots, backups, run log, diagnostics): kept apart from the reports
$PassDir = RootPath ([string](Cfg 'paths.passportsDir' 'Passports'))     # PC passports (pc_info_<PC>.json) are stored here
$Stamp   = Get-Date -Format ([string](Cfg 'reports.dateFormat' 'yyyyMMdd'))
$RptName = ([string](Cfg 'reports.fileName' '{pc}_report_{date}.html')).Replace('{pc}', $env:COMPUTERNAME).Replace('{date}', $Stamp)
if ($RptName -notmatch '\.html$') { $RptName += '.html' }
$Out       = Join-Path $OutDir $RptName
$StartTime = Get-Date

# one-time move of service files from the reports folder (versions before 1.4.0)
function Move-LegacyServiceFiles {
    try {
        New-Item -ItemType Directory -Force $SvcDir | Out-Null
        foreach ($m in @(@('_state', 'state'), @('_backup', 'backup'), @('_debug', 'debug'), @('_last_inventory.json', 'last_inventory.json'), @('_last_run.log', 'last_run.log'), @('_pending_rows.csv', 'pending_rows.csv'), @('_remote_search.txt', 'remote_search.txt'))) {
            $from = Join-Path $OutDir $m[0]; $to = Join-Path $SvcDir $m[1]
            if ((Test-Path -LiteralPath $from) -and -not (Test-Path -LiteralPath $to)) { Move-Item -LiteralPath $from -Destination $to -Force -ErrorAction SilentlyContinue }
        }
    } catch { }
}

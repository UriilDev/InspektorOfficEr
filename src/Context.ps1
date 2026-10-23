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
$PassDir = RootPath ([string](Cfg 'paths.passportsDir' 'Passports'))     # PC passports (pc_info_<PC>.json) are stored here
$Stamp   = Get-Date -Format ([string](Cfg 'reports.dateFormat' 'yyyyMMdd'))
$RptName = ([string](Cfg 'reports.fileName' '{pc}_report_{date}.html')).Replace('{pc}', $env:COMPUTERNAME).Replace('{date}', $Stamp)
if ($RptName -notmatch '\.html$') { $RptName += '.html' }
$Out       = Join-Path $OutDir $RptName
$StartTime = Get-Date

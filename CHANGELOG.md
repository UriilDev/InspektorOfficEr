# Changelog

## 1.0.2
- Source split into src/*.ps1, single portable Inspektor.ps1 is built by build.ps1 (CI checks it is up to date).
- Log with levels (config log.level), new switch -Diagnose: writes Raports\_debug\diagnose_<PC>_<time>.txt.
- External programs (HopToDesk CLI, robocopy) run with a hard timeout (config timeouts.hopToDeskCliSec, timeouts.robocopySec).
- A failing collector or WMI class no longer aborts the run: the value becomes "none" / the section is empty, the reason is logged.
- robocopy /B is skipped when not elevated; a warning is shown when the script is not run as Administrator.
- config.json: new optional keys "log" and "timeouts" (defaults are built in, existing files keep working). No Excel format changes.

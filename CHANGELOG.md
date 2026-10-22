# Changelog

## 1.1.0
- Detection: AnyDesk is also looked up via `AnyDesk.exe --get-id` of an installed copy, extra folders (`anyDesk.extraConfigDirs`, `anyDesk.extraPaths`), portable copies on the desktop / in downloads. HopToDesk: per-user install and uninstall-entry paths (`hopToDesk.extraPaths`).
- **Cell text change (no migration needed):** when AnyDesk / HopToDesk is present but its ID cannot be read, the cell now says "Установлен, ID не найден" instead of "Нет". A real or hand-typed ID in the workbook is never replaced by it.
- Deep Freeze is no longer triggered by other Faronics products (patterns and folders are specific to Deep Freeze). Presence is reported; frozen / thawed state is still not claimed.
- Quick check: thresholds in config.json section "checks" (all optional, defaults built in): uptimeDaysWarn 30, ramGbWarn 4, diskFreePctWarn 20, diskFreePctBad 10, diskFreeGbBad 5, osSupportWarnDays 90, changeFreeGb 5, osSupport (own end-of-support dates by build).
- Quick check: OS support is decided by Windows build and edition with end dates (Windows 10 22H2 ended 2025-10-14, Windows 11 24H2 Home/Pro 2026-10-13 and so on); antivirus state (on / off / outdated signatures) from SecurityCenter2; firewall falls back to the registry on Windows 7; every problem gets a short "what to do" line; unknown data is skipped instead of guessed.
- Report: "what to fix first" line, "what changed since the previous report of this PC" (snapshot in Raports\_state\<PC>.json: OS, RAM, free space, disks, antivirus, installed / removed / updated programs), faster table build for 500+ programs, debounced search with a counter, status words next to colours, focus outline, print layout for long tables.
- Excel: columns are found by header text (inserted / reordered columns are fine; a column that is not found is skipped with a warning, nothing is overwritten); only cells whose value changed are written (formulas, number cells and styles stay); a protected sheet or merged cells stop the write with a clear message and the row goes to `_pending_rows.csv`; the configured sheet name is used when the workbook has several sheets; a few title rows above the header are tolerated; the update is made on a copy that is verified before it replaces the workbook. Backups as before.
- `_last_inventory.json` now contains the report link.
- Tests and CI are not part of this project (build.ps1 -Check remains as a local drift check).

## 1.0.2
- Source split into src/*.ps1, single portable Inspektor.ps1 is built by build.ps1 (CI checks it is up to date).
- Log with levels (config log.level), new switch -Diagnose: writes Raports\_debug\diagnose_<PC>_<time>.txt.
- External programs (HopToDesk CLI, robocopy) run with a hard timeout (config timeouts.hopToDeskCliSec, timeouts.robocopySec).
- A failing collector or WMI class no longer aborts the run: the value becomes "none" / the section is empty, the reason is logged.
- robocopy /B is skipped when not elevated; a warning is shown when the script is not run as Administrator.
- config.json: new optional keys "log" and "timeouts" (defaults are built in, existing files keep working). No Excel format changes.

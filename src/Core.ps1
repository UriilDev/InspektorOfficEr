# ===================== CORE: strings, config, shared state =====================
$AppName = 'InspektorOfficEr'; $AppVer = '1.0.2'

# ---------- Cyrillic-safe strings: sources are pure ASCII, texts are written as \uXXXX ----------
function U([string]$s) { [regex]::Replace($s, '\\u([0-9a-fA-F]{4})', { param($m) [string][char][Convert]::ToInt32($m.Groups[1].Value, 16) }) }

# ---------- configuration ----------
# Import-InspektorConfig <path> : parsed config.json, or $null (file missing / invalid -> built-in defaults)
function Import-InspektorConfig([string]$path) {
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return $null }
    try { return ([IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json) }
    catch { Write-Host "config.json is invalid, built-in defaults are used: $($_.Exception.Message)" -ForegroundColor Yellow; return $null }
}
# Cfg 'section.key' <default> : value from config.json, or the default if the key is missing / empty ($false is a value)
function Cfg([string]$path, $default) {
    $o = $script:Cfg
    foreach ($k in $path.Split('.')) {
        if ($null -eq $o) { return $default }
        $p = $o.PSObject.Properties[$k]
        if (-not $p) { return $default }
        $o = $p.Value
    }
    if ($null -eq $o -or ($o -is [string] -and $o.Trim() -eq '')) { return $default }
    $o
}
# relative paths are resolved against the script folder ($Root)
function RootPath([string]$p) { if ([IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $Root $p } }

function Finish($code) { try { Stop-Transcript | Out-Null } catch { }; exit $code }

# ---------- shared state ----------
$NO = (U '\u041d\u0435\u0442')
$script:Src = @{ Passport = ''; AnyDesk = ''; Hop = ''; Freeze = '' }   # where each value came from (printed to console)

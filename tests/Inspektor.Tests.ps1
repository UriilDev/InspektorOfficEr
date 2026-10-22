#requires -Version 5.1
# Pester 5 tests. Run:  Invoke-Pester .\tests
# Sources in src\ are dot-sourced, so every function can be tested and mocked on its own.

BeforeDiscovery {
    $script:IsWin = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
}

BeforeAll {
    $script:Repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Src  = Join-Path $script:Repo 'src'
    $script:Cfg  = $null
    $Root = $script:Repo
    foreach ($m in 'Core', 'Log', 'Report', 'Collectors', 'Passport', 'Xlsx', 'Inventory') {
        . (Join-Path $script:Src ($m + '.ps1'))
    }
    function Get-RepoScripts {
        Get-ChildItem $script:Repo -Recurse -Include *.ps1, *.psm1, *.psd1 -File |
            Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules)[\\/]' }
    }
}

Describe 'Repository hygiene' {
    It 'all PowerShell files are pure ASCII' {
        foreach ($f in Get-RepoScripts) {
            $bytes = [IO.File]::ReadAllBytes($f.FullName)
            @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0 -Because $f.Name
        }
    }
    It 'all PowerShell files use CRLF only' {
        foreach ($f in Get-RepoScripts) {
            $t = [IO.File]::ReadAllText($f.FullName)
            ([regex]::Matches($t, "(?<!`r)`n")).Count | Should -Be 0 -Because $f.Name
        }
    }
    It 'all PowerShell files parse without errors' {
        foreach ($f in Get-RepoScripts) {
            $e = $null; $t = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$t, [ref]$e)
            @($e).Count | Should -Be 0 -Because $f.Name
        }
    }
    It 'Inspektor.ps1 is up to date with src (run build.ps1)' {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('ioe_' + [guid]::NewGuid().ToString('N') + '.ps1')
        try {
            & (Join-Path $script:Repo 'build.ps1') -OutFile $tmp | Out-Null
            ([IO.File]::ReadAllText($tmp) -replace "`r`n", "`n") | Should -BeExactly (([IO.File]::ReadAllText((Join-Path $script:Repo 'Inspektor.ps1'))) -replace "`r`n", "`n")
        } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }
    It 'Inspektor.ps1 keeps its command-line switches' {
        $e = $null; $t = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Repo 'Inspektor.ps1'), [ref]$t, [ref]$e)
        $names = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }) | Sort-Object
        ($names -join ',') | Should -Be 'Diagnose,NoHopCli,NoPrompt,SkipExcel,SkipReport'
    }
    It 'config.json is valid JSON with the expected sections' {
        $c = [IO.File]::ReadAllText((Join-Path $script:Repo 'config.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
        foreach ($s in 'paths', 'features', 'passport', 'excel', 'freeze', 'reports', 'backup', 'ui', 'log', 'timeouts') {
            $c.PSObject.Properties.Name | Should -Contain $s
        }
        @($c.excel.headers).Count | Should -Be 11
    }
}

Describe 'Core: U' {
    It 'converts \uXXXX escapes' {
        (U '\u041f\u0440\u0438\u0432\u0435\u0442') | Should -BeExactly ([string]::Join('', [char[]](0x041F, 0x0440, 0x0438, 0x0432, 0x0435, 0x0442)))
    }
    It 'leaves plain text untouched' { (U 'abc 123') | Should -BeExactly 'abc 123' }
}

Describe 'Core: configuration' {
    BeforeEach { $script:Cfg = $null }

    It 'returns the default when there is no config' { (Cfg 'a.b' 'dflt') | Should -Be 'dflt' }
    It 'reads nested values' {
        $script:Cfg = '{"a":{"b":"val"}}' | ConvertFrom-Json
        (Cfg 'a.b' 'dflt') | Should -Be 'val'
    }
    It 'respects an explicit false' {
        $script:Cfg = '{"features":{"report":false}}' | ConvertFrom-Json
        (Cfg 'features.report' $true) | Should -BeFalse
    }
    It 'treats an empty string as missing' {
        $script:Cfg = '{"paths":{"workbook":"  "}}' | ConvertFrom-Json
        (Cfg 'paths.workbook' 'dflt') | Should -Be 'dflt'
    }
    It 'returns the default for a missing key' {
        $script:Cfg = '{"a":{}}' | ConvertFrom-Json
        (Cfg 'a.zzz' 5) | Should -Be 5
    }
    It 'Import-InspektorConfig returns null for a missing file' {
        Import-InspektorConfig (Join-Path $TestDrive 'nope.json') | Should -BeNullOrEmpty
    }
    It 'Import-InspektorConfig returns null for invalid JSON' {
        $p = Join-Path $TestDrive 'bad.json'; [IO.File]::WriteAllText($p, '{ not json')
        Import-InspektorConfig $p 6>$null | Should -BeNullOrEmpty
    }
    It 'Import-InspektorConfig parses a valid file' {
        $p = Join-Path $TestDrive 'ok.json'; [IO.File]::WriteAllText($p, '{"x":{"y":1}}')
        (Import-InspektorConfig $p).x.y | Should -Be 1
    }
    It 'RootPath resolves relative paths against $Root' {
        $Root = $TestDrive
        (RootPath 'Raports') | Should -Be (Join-Path $TestDrive 'Raports')
    }
    It 'RootPath keeps absolute paths' {
        $abs = [IO.Path]::GetFullPath((Join-Path $TestDrive 'x'))
        (RootPath $abs) | Should -Be $abs
    }
}

Describe 'Log' {
    BeforeEach { $script:Cfg = $null; $Diagnose = $false; $script:LogBuf.Clear() }

    It 'keeps every level in the buffer' {
        Write-Log DEBUG 'dbg' 6>$null; Write-Log WARN 'wrn' 6>$null
        @($script:LogBuf).Count | Should -Be 2
        $script:LogBuf[0] | Should -Match '\[DEBUG\] dbg'
    }
    It 'does not print DEBUG at the default level' {
        $o = Write-Log DEBUG 'hidden' 6>&1 | Out-String
        $o | Should -Not -Match 'hidden'
    }
    It 'prints WARN at the default level' {
        $o = Write-Log WARN 'shown' 6>&1 | Out-String
        $o | Should -Match 'shown'
    }
    It 'prints DEBUG with -Diagnose' {
        $Diagnose = $true
        $o = Write-Log DEBUG 'verbose' 6>&1 | Out-String
        $o | Should -Match 'verbose'
    }
    It 'honours log.level from config.json' {
        $script:Cfg = '{"log":{"level":"ERROR"}}' | ConvertFrom-Json
        $o = Write-Log WARN 'quiet' 6>&1 | Out-String
        $o | Should -Not -Match 'quiet'
    }
    It 'Save-DiagnoseLog writes _debug\diagnose_*.txt with the log' {
        $Drive = ''; $SkipReport = $false; $SkipExcel = $false; $NoHopCli = $false; $NoPrompt = $false
        Write-Log INFO 'marker-line' 6>$null
        $f = Save-DiagnoseLog $TestDrive
        $f | Should -Match 'diagnose_'
        [IO.File]::ReadAllText($f) | Should -Match 'marker-line'
    }
}

Describe 'Invoke-External' {
    It 'captures output and exit code' {
        if ($script:IsWin) { $r = Invoke-External 'cmd.exe' '/c echo hello' 10 } else { $r = Invoke-External '/bin/sh' '-c "echo hello"' 10 }
        $r.TimedOut | Should -BeFalse
        $r.ExitCode | Should -Be 0
        $r.Stdout.Trim() | Should -Be 'hello'
    }
    It 'kills a process that exceeds the timeout' {
        if ($script:IsWin) { $r = Invoke-External 'ping.exe' '-n 30 127.0.0.1' 1 } else { $r = Invoke-External '/bin/sh' '-c "sleep 30"' 1 }
        $r.TimedOut | Should -BeTrue
        $r.ExitCode | Should -BeNullOrEmpty
    }
    It 'does not throw when the program does not exist' {
        $r = Invoke-External (Join-Path $TestDrive 'no_such_program.exe') '' 2
        $r.Error | Should -Not -BeNullOrEmpty
    }
}

Describe 'Collectors: error isolation' {
    It 'Tm returns "none" instead of throwing when a collector fails' {
        $r = Tm 'Broken' { throw 'boom' } 6>$null
        $r | Should -Be $NO
    }
    It 'Tm passes the value through on success' {
        (Tm 'Ok' { 'value' } 6>$null) | Should -Be 'value'
    }
    It 'Get-AnyDeskId reads the ID from system.conf' {
        $env:ProgramData = Join-Path $TestDrive 'pd'
        New-Item -ItemType Directory -Force (Join-Path $env:ProgramData 'AnyDesk') | Out-Null
        [IO.File]::WriteAllText((Join-Path $env:ProgramData 'AnyDesk\system.conf'), "ad.anynet.id=123456789`r`nad.other=1`r`n")
        Mock Get-UserProfileDirs { @() }
        (Get-AnyDeskId 6>$null) | Should -Be '123456789'
    }
    It 'Get-AnyDeskId returns "none" when nothing is installed' {
        $env:ProgramData = Join-Path $TestDrive 'empty'; $env:APPDATA = Join-Path $TestDrive 'emptyroam'
        Mock Get-UserProfileDirs { @() }
        (Get-AnyDeskId 6>$null) | Should -Be $NO
    }
}

Describe 'Passport' {
    It 'reads a JSON passport with English keys' {
        $p = Join-Path $TestDrive 'p1.json'
        [IO.File]::WriteAllText($p, '{"Floor":"2","Room":"205","Place":"3","User":"user01"}')
        $r = Read-PassportFile $p
        $r.Floor | Should -Be '2'; $r.Room | Should -Be '205'; $r.Place | Should -Be '3'; $r.User | Should -Be 'user01'
    }
    It 'reads a JSON passport with Russian keys' {
        $p = Join-Path $TestDrive 'p2.json'
        $json = '{"' + (U '\u042d\u0442\u0430\u0436') + '":"1","' + (U '\u041a\u0430\u0431\u0438\u043d\u0435\u0442') + '":"101"}'
        [IO.File]::WriteAllText($p, $json, (New-Object Text.UTF8Encoding($false)))
        $r = Read-PassportFile $p
        $r.Floor | Should -Be '1'; $r.Room | Should -Be '101'
    }
    It 'reads a plain key: value passport' {
        $p = Join-Path $TestDrive 'p3.txt'
        [IO.File]::WriteAllText($p, "Floor: 3`r`nRoom = 7`r`nUser: user02`r`n")
        $r = Read-PassportFile $p
        $r.Floor | Should -Be '3'; $r.Room | Should -Be '7'; $r.User | Should -Be 'user02'
    }
    It 'returns null when no known keys are present' {
        $p = Join-Path $TestDrive 'p4.txt'; [IO.File]::WriteAllText($p, "foo: bar`r`n")
        Read-PassportFile $p | Should -BeNullOrEmpty
    }
    It 'Read-TextSmart decodes UTF-16 LE with BOM' {
        $p = Join-Path $TestDrive 'u16.txt'
        $b = [byte[]]@(0xFF, 0xFE) + [Text.Encoding]::Unicode.GetBytes('Floor: 9')
        [IO.File]::WriteAllBytes($p, $b)
        (Read-TextSmart $p) | Should -Be 'Floor: 9'
    }
    It 'Read-TextSmart falls back to cp1251 for non-UTF8 bytes' -Skip:(-not $script:IsWin) {
        $p = Join-Path $TestDrive 'cp1251.txt'
        [IO.File]::WriteAllBytes($p, [byte[]](0xCF, 0xF0, 0xE8))   # cp1251 bytes
        (Read-TextSmart $p) | Should -Be (U '\u041f\u0440\u0438')
    }
}

Describe 'Excel helpers' {
    It 'Col-Letter / Col-Index round trip' {
        foreach ($n in 1, 2, 26, 27, 52, 53, 702, 703) { (Col-Index (Col-Letter $n)) | Should -Be $n }
        (Col-Letter 27) | Should -Be 'AA'
    }
    It 'Merge-Id: a real new value wins' { (Merge-Id 'old' 'new' 'No') | Should -Be 'new' }
    It 'Merge-Id: "none" never overwrites a stored value' { (Merge-Id 'old' 'No' 'No') | Should -Be 'old' }
    It 'Merge-Id: nothing known -> none' { (Merge-Id '' 'No' 'No') | Should -Be 'No' }

    Context 'Merge-Freeze' {
        BeforeEach { $script:Cfg = $null }
        It 'keeps the human-written state when the product is the same' {
            (Merge-Freeze 'Deep Freeze: frozen' 'Deep Freeze (installed)' 'No') | Should -Be 'Deep Freeze: frozen'
        }
        It 'takes the new value when the product changed' {
            (Merge-Freeze 'Deep Freeze: frozen' 'Shadow Defender (installed)' 'No') | Should -Be 'Shadow Defender (installed)'
        }
        It 'returns none when the product disappeared' {
            (Merge-Freeze 'Deep Freeze: frozen' 'No' 'No') | Should -Be 'No'
        }
        It 'keeps a manual note that is not a known product' {
            (Merge-Freeze 'Dual Boot' 'No' 'No') | Should -Be 'Dual Boot'
        }
        It 'knows extraProducts from config.json' {
            $script:Cfg = '{"freeze":{"extraProducts":[{"name":"MyGuard"}]}}' | ConvertFrom-Json
            (Get-FreezeNames) | Should -Contain 'MyGuard'
        }
        It 'honours disableBuiltin' {
            $script:Cfg = '{"freeze":{"disableBuiltin":["Shadow Defender"]}}' | ConvertFrom-Json
            (Get-FreezeNames) | Should -Not -Contain 'Shadow Defender'
        }
    }
}

Describe 'Excel: OpenXML workbook' {
    BeforeAll {
        $script:Cfg = $null
        function New-Rec($pc) {
            [pscustomobject]@{ Floor = '1'; Room = '5'; Place = '2'; User = 'user01'; UserFromPassport = $true
                AnyDesk = '123 456 789'; Hop = $NO; State = 'OK'; Freeze = $NO; Pc = $pc
                ReportRel = ('Raports\' + $pc + '_report.html'); ReportLabel = 'Report' }
        }
        function Read-SheetXml($path) {
            $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
            $zip = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Read)
            try {
                $e = $zip.GetEntry('xl/worksheets/sheet1.xml')
                $sr = New-Object IO.StreamReader($e.Open(), [Text.Encoding]::UTF8); try { $sr.ReadToEnd() } finally { $sr.Dispose() }
            } finally { $zip.Dispose(); $fs.Dispose() }
        }
    }
    BeforeEach {
        $Root = $TestDrive
        $OutDir = Join-Path $TestDrive 'Raports'
        $script:Book = Join-Path $TestDrive ('book_' + [guid]::NewGuid().ToString('N') + '.xlsx')
    }
    It 'creates a new workbook and adds a row' {
        $r = Update-InventoryXlsx $script:Book (New-Rec 'PC-001') $NO
        $r | Should -Match 'created file'
        Test-Path $script:Book | Should -BeTrue
        (Read-SheetXml $script:Book) | Should -Match 'PC-001'
    }
    It 'updates the same PC instead of adding a duplicate' {
        [void](Update-InventoryXlsx $script:Book (New-Rec 'PC-001') $NO)
        $r = Update-InventoryXlsx $script:Book (New-Rec 'PC-001') $NO
        $r | Should -Match 'updated row 2 \(match: PC name\)'
        ([regex]::Matches((Read-SheetXml $script:Book), '<row ')).Count | Should -Be 2   # header + one data row
    }
    It 'adds a separate row for another PC' {
        [void](Update-InventoryXlsx $script:Book (New-Rec 'PC-001') $NO)
        $b = New-Rec 'PC-002'; $b.Room = '6'; $b.AnyDesk = '987 654 321'
        (Update-InventoryXlsx $script:Book $b $NO) | Should -Match 'added row 3'
    }
    It 'matches by AnyDesk ID when the PC name is new' {
        [void](Update-InventoryXlsx $script:Book (New-Rec 'PC-001') $NO)
        $b = New-Rec 'PC-NEW'; $b.Room = '9'
        (Update-InventoryXlsx $script:Book $b $NO) | Should -Match 'match: AnyDesk ID'
    }
    It 'writes a HYPERLINK formula to the report' {
        [void](Update-InventoryXlsx $script:Book (New-Rec 'PC-001') $NO)
        (Read-SheetXml $script:Book) | Should -Match 'HYPERLINK'
    }
    It 'makes a backup of an existing workbook' {
        [void](Update-InventoryXlsx $script:Book (New-Rec 'PC-001') $NO)
        [void](Update-InventoryXlsx $script:Book (New-Rec 'PC-001') $NO)
        @(Get-ChildItem (Join-Path $OutDir '_backup') -Filter *.xlsx).Count | Should -Be 1
    }
    It 'fails (so the caller can save a pending row) when the file is locked' {
        [void](Update-InventoryXlsx $script:Book (New-Rec 'PC-001') $NO)
        $fs = [IO.File]::Open($script:Book, 'Open', 'ReadWrite', 'None')
        try { { Update-InventoryXlsx $script:Book (New-Rec 'PC-001') $NO } | Should -Throw }
        finally { $fs.Dispose() }
    }
}

Describe 'Inventory: pending rows' {
    It 'Save-PendingRow writes a CSV with a header and one record' {
        $OutDir = Join-Path $TestDrive 'out'; New-Item -ItemType Directory $OutDir | Out-Null
        $rec = [pscustomobject]@{ Floor = '1'; Room = '5'; Place = '2'; User = 'user01'; AnyDesk = '123'; Hop = 'No'; State = 'OK'; Freeze = 'No'; Pc = 'PC-001' }
        $f = Save-PendingRow $rec
        $lines = @([IO.File]::ReadAllLines($f))
        $lines.Count | Should -Be 2
        $lines[1] | Should -Match 'PC-001'
    }
}

Describe 'Report' -Skip:(-not $script:IsWin) {
    # Windows-only: needs the real WMI/CIM cmdlets so that Pester can mock them.
    BeforeAll {
        $script:Cfg = $null
        Mock Get-CimInstance {
            switch -Regex ($ClassName) {
                'Win32_ComputerSystem'  { [pscustomobject]@{ Manufacturer = 'Vendor'; Model = 'Model X'; TotalPhysicalMemory = 8GB; Name = 'PC-001'; UserName = 'user01'; Domain = 'WORKGROUP' } }
                'Win32_OperatingSystem' { [pscustomobject]@{ Caption = 'Microsoft Windows 10 Pro'; Version = '10.0.19045'; BuildNumber = '19045'; OSArchitecture = '64-bit'; LastBootUpTime = (Get-Date).AddDays(-3); InstallDate = (Get-Date).AddYears(-1); FreePhysicalMemory = 4194304; TotalVisibleMemorySize = 8388608 } }
                default { @() }
            }
        }
        Mock Get-Uninstall { @([pscustomobject]@{ DisplayName = 'Sample App'; DisplayVersion = '1.0'; Publisher = 'Vendor' }) }
        Mock Get-PhysicalDisk { @() }
        Mock Get-Service { @() }
        Mock Get-NetFirewallProfile { @() }
    }
    It 'builds a self-contained HTML file with every placeholder replaced' {
        $out = Join-Path $TestDrive 'r.html'
        New-InspectorReport $out
        $html = [IO.File]::ReadAllText($out, [Text.Encoding]::UTF8)
        $html | Should -Match '<!DOCTYPE html>'
        $html | Should -Match 'PC-001'
        $html | Should -Not -Match '\{\{[A-Z_]+\}\}'
    }
}

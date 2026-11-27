# Pester shares variables between BeforeDiscovery/BeforeAll/BeforeEach and the It blocks, which the
# analyzer can't see. Test helpers that create files don't need -WhatIf.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester scoping')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test helpers')]
param()

BeforeDiscovery {
    $onWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TestHelpers.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '../Get-LockingProcesses/Get-LockingProcesses.psd1') -Force
}

AfterAll {
    Remove-Module Get-LockingProcesses, TestHelpers -ErrorAction SilentlyContinue
}

Describe 'Get-LockingProcesses' {

    Context 'parsing handle.exe output' -Skip:(-not $onWindows) {
        # handle.exe is mocked: these tests only check how its output is turned into objects.

        It 'returns one object per handle line' {
            Mock -ModuleName Get-LockingProcesses Invoke-Handle {
                'pwsh.exe           pid: 2796   type: File          LEGION5PRO\Prateek         2E4: C:\Program Files\PowerShell\7\pwsh.dll'
                'explorer.exe       pid: 488    type: File          LEGION5PRO\Prateek         1A0: C:\Users\Prateek\Desktop'
            }

            $result = @(Get-LockingProcesses 'C:\Some\Path')

            $result | Should -HaveCount 2
            $result[0].FullName | Should -Be 'pwsh.exe'
            $result[0].Name | Should -Be 'pwsh'
            $result[0].ID | Should -Be '2796'
            $result[0].Type | Should -Be 'File'
            $result[0].User | Should -Be 'LEGION5PRO\Prateek'
            $result[0].Path | Should -Be 'C:\Program Files\PowerShell\7\pwsh.dll'
            $result[0].toString | Should -Be 'pid: 2796, user: LEGION5PRO\Prateek, image: pwsh.exe'
            $result[1].Name | Should -Be 'explorer'
            $result[1].Path | Should -Be 'C:\Users\Prateek\Desktop'
        }

        It 'passes -Path to handle.exe' {
            Mock -ModuleName Get-LockingProcesses Invoke-Handle { }

            Get-LockingProcesses -Path 'C:\Folder With Space\file.txt' -WarningAction SilentlyContinue

            Should -Invoke -ModuleName Get-LockingProcesses Invoke-Handle -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'C:\Folder With Space\file.txt'
            }
        }

        It 'parses image name <Image>' -ForEach @(
            @{ Image = 'Microsoft.Photos.exe'; Name = 'Microsoft.Photos' }
            @{ Image = 'msedge-webview2.exe'; Name = 'msedge-webview2' }
            @{ Image = 'Code - Insiders.exe'; Name = 'Code - Insiders' }
            @{ Image = 'System'; Name = 'System' }
        ) {
            $line = '{0,-18} pid: 1234   type: File          NT AUTHORITY\SYSTEM        3C8: C:\Data\file.txt' -f $Image
            Mock -ModuleName Get-LockingProcesses Invoke-Handle { $line }

            $result = @(Get-LockingProcesses 'C:\Data')

            $result | Should -HaveCount 1
            $result[0].FullName | Should -Be $Image
            $result[0].Name | Should -Be $Name
            $result[0].User | Should -Be 'NT AUTHORITY\SYSTEM'
            $result[0].Path | Should -Be 'C:\Data\file.txt'
        }

        It 'parses the Handle 5 format (handle column without a colon)' {
            Mock -ModuleName Get-LockingProcesses Invoke-Handle {
                'pwsh.exe           pid: 25512  type: File          LEGION5PRO\Prateek        81008X C:\Users\Prateek\AppData\Local\Temp\lock me.txt'
                'System             pid: 4      type: File          NT AUTHORITY\SYSTEM       1A4X C:\Data\file.txt'
            }

            $result = @(Get-LockingProcesses 'C:\')

            $result | Should -HaveCount 2
            $result[0].ID | Should -Be '25512'
            $result[0].User | Should -Be 'LEGION5PRO\Prateek'
            $result[0].Path | Should -Be 'C:\Users\Prateek\AppData\Local\Temp\lock me.txt'
            $result[1].User | Should -Be 'NT AUTHORITY\SYSTEM'
            $result[1].Path | Should -Be 'C:\Data\file.txt'
        }

        It 'keeps paths with spaces and colons, and trims trailing spaces' {
            Mock -ModuleName Get-LockingProcesses Invoke-Handle {
                'app.exe            pid: 42     type: File          DOMAIN\user                44: C:\My Files\a: b.txt   '
            }

            (Get-LockingProcesses 'C:\My Files').Path | Should -Be 'C:\My Files\a: b.txt'
        }

        It 'warns when <Case>' -ForEach @(
            @{ Case = 'no handles are found'; Output = @('No matching handles found.') }
            @{ Case = 'handle.exe prints nothing'; Output = @() }
            @{ Case = 'handle.exe fails'; Output = @('Initialization error:', 'Make sure that you are an administrator.') }
        ) {
            Mock -ModuleName Get-LockingProcesses Invoke-Handle { $Output }

            $result = Get-LockingProcesses 'C:\Nothing' -WarningVariable warnings -WarningAction SilentlyContinue

            $result | Should -BeNullOrEmpty
            "$warnings" | Should -Match 'No matching handles found'
        }

        It 'has the glp alias and the -name alias for -Path' {
            Mock -ModuleName Get-LockingProcesses Invoke-Handle {
                'a.exe              pid: 1      type: File          D\u                        4: C:\x'
            }

            (glp -name 'C:\x').ID | Should -Be '1'
        }
    }

    Context 'finding Handle' -Skip:(-not $onWindows) {
        # Nothing is downloaded here: PATH, the download and the signature check are all mocked.

        BeforeEach {
            $cache = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $originalCache = InModuleScope Get-LockingProcesses { $script:HandleCacheDir }
            InModuleScope Get-LockingProcesses -Parameters @{ Cache = $cache } { param($Cache) $script:HandleCacheDir = $Cache }
            $exeName = InModuleScope Get-LockingProcesses { Get-HandleExeName }

            Mock -ModuleName Get-LockingProcesses Get-Command { }
            # Fake download: a zip holding empty handle exes.
            Mock -ModuleName Get-LockingProcesses Invoke-WebRequest {
                $src = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
                foreach ($name in 'handle.exe', 'handle64.exe', 'handle64a.exe', 'Eula.txt') { $null = New-TestFile (Join-Path $src $name) }
                Compress-Archive -Path (Join-Path $src '*') -DestinationPath $OutFile
            }
            Mock -ModuleName Get-LockingProcesses Test-MicrosoftSignature { $true }
        }

        AfterEach {
            InModuleScope Get-LockingProcesses -Parameters @{ Cache = $originalCache } { param($Cache) $script:HandleCacheDir = $Cache }
        }

        It 'picks the handle build that matches this machine' {
            $expected = switch ("$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)") {
                'Arm64' { 'handle64a.exe' }
                'X64' { 'handle64.exe' }
                default { 'handle.exe' }
            }
            $exeName | Should -Be $expected
        }

        It 'does not ship handle with the module (its license does not allow it)' {
            $moduleDir = Join-Path $PSScriptRoot '../Get-LockingProcesses'
            @(Get-ChildItem -LiteralPath $moduleDir -Filter 'handle*.exe') | Should -HaveCount 0
            (Import-PowerShellDataFile (Join-Path $moduleDir 'Get-LockingProcesses.psd1')).FileList | Should -Be @('Get-LockingProcesses.psm1')
        }

        It 'uses handle from PATH when it is there' {
            Mock -ModuleName Get-LockingProcesses Get-Command { [pscustomobject]@{ Source = 'C:\Tools\handle64.exe' } }

            InModuleScope Get-LockingProcesses { Get-HandlePath } | Should -Be 'C:\Tools\handle64.exe'
            Should -Invoke -ModuleName Get-LockingProcesses Invoke-WebRequest -Times 0 -Exactly
        }

        It 'downloads handle once, warns about the license, and reuses the download' {
            $output = @(InModuleScope Get-LockingProcesses { Get-HandlePath 3>&1 })
            $warnings = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            $first = $output | Where-Object { $_ -is [string] }
            $second = @(InModuleScope Get-LockingProcesses { Get-HandlePath 3>&1 })

            $warnings | Should -HaveCount 1
            $second | Should -HaveCount 1 -Because 'the second call neither downloads nor warns'
            $first | Should -Be (Join-Path $cache $exeName)
            $second | Should -Be $first
            Test-Path -LiteralPath (Join-Path $cache 'Eula.txt') | Should -BeTrue
            "$warnings" | Should -Match 'license-terms'
            Should -Invoke -ModuleName Get-LockingProcesses Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://download.sysinternals.com/files/Handle.zip'
            }
        }

        It 'does not use a download that is not signed by Microsoft' {
            Mock -ModuleName Get-LockingProcesses Test-MicrosoftSignature { $false }

            { InModuleScope Get-LockingProcesses { Get-HandlePath } 3>$null } | Should -Throw '*not signed by Microsoft*'
            Test-Path -LiteralPath (Join-Path $cache $exeName) | Should -BeFalse
        }

        It 'writes an error when Handle cannot be downloaded' {
            Mock -ModuleName Get-LockingProcesses Invoke-WebRequest { throw 'No network' }

            Get-LockingProcesses 'C:\Data' -ErrorVariable errors -ErrorAction SilentlyContinue 3>$null

            "$errors" | Should -Match 'Could not run Sysinternals Handle: No network'
        }
    }

    Context 'with the real handle.exe' -Skip:(-not $onWindows) {

        It 'finds this PowerShell process holding a file open' -Tag 'Integration' {
            # Runs the real Handle: from PATH, else the download folder, else downloaded from Microsoft first
            # (that is how CI tests the real download and signature check). -accepteula keeps it from waiting
            # for a prompt. Without admin rights it still sees handles of the current user's processes.
            $file = New-TestFile (Join-Path $TestDrive "locked-$([guid]::NewGuid().ToString('N')).txt")
            $stream = Lock-TestFile $file
            try {
                $result = @(Get-LockingProcesses $file -WarningAction SilentlyContinue)
            }
            finally {
                $stream.Dispose()
            }

            $result.ID | Should -Contain "$PID"
            ($result | Where-Object ID -EQ "$PID").Path | Should -Contain $file
        }
    }

    Context 'macOS/Linux' -Skip:$onWindows {

        It 'writes an error and does not run handle.exe' {
            Mock -ModuleName Get-LockingProcesses Invoke-Handle { }

            Get-LockingProcesses '/tmp' -ErrorVariable errors -ErrorAction SilentlyContinue

            "$errors" | Should -Match 'only works on Windows'
            Should -Invoke -ModuleName Get-LockingProcesses Invoke-Handle -Times 0 -Exactly
        }
    }
}

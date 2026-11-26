BeforeDiscovery {
    $onWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TestHelpers.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '../GetLockingProcess/GetLockingProcess.psd1') -Force
}

AfterAll {
    Remove-Module GetLockingProcess, TestHelpers -ErrorAction SilentlyContinue
}

Describe 'Get-LockingProcesses' {

    Context 'parsing handle.exe output' -Skip:(-not $onWindows) {
        # handle.exe is mocked: these tests only check how its output is turned into objects.

        It 'returns one object per handle line' {
            Mock -ModuleName GetLockingProcess Invoke-Handle {
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
            Mock -ModuleName GetLockingProcess Invoke-Handle { }

            Get-LockingProcesses -Path 'C:\Folder With Space\file.txt' -WarningAction SilentlyContinue

            Should -Invoke -ModuleName GetLockingProcess Invoke-Handle -Times 1 -Exactly -ParameterFilter {
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
            Mock -ModuleName GetLockingProcess Invoke-Handle { $line }

            $result = @(Get-LockingProcesses 'C:\Data')

            $result | Should -HaveCount 1
            $result[0].FullName | Should -Be $Image
            $result[0].Name | Should -Be $Name
            $result[0].User | Should -Be 'NT AUTHORITY\SYSTEM'
            $result[0].Path | Should -Be 'C:\Data\file.txt'
        }

        It 'parses the Handle 5 format (handle column without a colon)' {
            Mock -ModuleName GetLockingProcess Invoke-Handle {
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
            Mock -ModuleName GetLockingProcess Invoke-Handle {
                'app.exe            pid: 42     type: File          DOMAIN\user                44: C:\My Files\a: b.txt   '
            }

            (Get-LockingProcesses 'C:\My Files').Path | Should -Be 'C:\My Files\a: b.txt'
        }

        It 'warns when <Case>' -ForEach @(
            @{ Case = 'no handles are found'; Output = @('No matching handles found.') }
            @{ Case = 'handle.exe prints nothing'; Output = @() }
            @{ Case = 'handle.exe fails'; Output = @('Initialization error:', 'Make sure that you are an administrator.') }
        ) {
            Mock -ModuleName GetLockingProcess Invoke-Handle { $Output }

            $result = Get-LockingProcesses 'C:\Nothing' -WarningVariable warnings -WarningAction SilentlyContinue

            $result | Should -BeNullOrEmpty
            "$warnings" | Should -Match 'No matching handles found'
        }

        It 'has the glp alias and the -name alias for -Path' {
            Mock -ModuleName GetLockingProcess Invoke-Handle {
                'a.exe              pid: 1      type: File          D\u                        4: C:\x'
            }

            (glp -name 'C:\x').ID | Should -Be '1'
        }
    }

    Context 'handle files' {

        It 'ships every file in the manifest FileList, including all three handle builds' {
            $moduleDir = Join-Path $PSScriptRoot '../GetLockingProcess'
            $fileList = (Import-PowerShellDataFile (Join-Path $moduleDir 'GetLockingProcess.psd1')).FileList

            $fileList | Should -Contain 'handle.exe'
            $fileList | Should -Contain 'handle64.exe'
            $fileList | Should -Contain 'handle64a.exe'
            foreach ($file in $fileList) {
                Test-Path -LiteralPath (Join-Path $moduleDir $file) | Should -BeTrue -Because "$file is in FileList"
            }
        }

        It 'picks the handle build that matches this machine' -Skip:(-not $onWindows) {
            $expected = switch ("$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)") {
                'Arm64' { 'handle64a.exe' }
                'X64' { 'handle64.exe' }
                default { 'handle.exe' }
            }
            InModuleScope GetLockingProcess { Get-HandleExeName } | Should -Be $expected
        }
    }

    Context 'with the real handle.exe' -Skip:(-not $onWindows) {

        It 'finds this PowerShell process holding a file open' -Tag 'Integration' {
            # Runs handle64.exe/handle.exe from the module folder; -accepteula keeps it from waiting
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
            Mock -ModuleName GetLockingProcess Invoke-Handle { }

            Get-LockingProcesses '/tmp' -ErrorVariable errors -ErrorAction SilentlyContinue

            "$errors" | Should -Match 'only works on Windows'
            Should -Invoke -ModuleName GetLockingProcess Invoke-Handle -Times 0 -Exactly
        }
    }
}

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$registryPaths = @(
    'HKCU:\Software\Classes\Directory\shell\SvnScope',
    'HKCU:\Software\Classes\Directory\Background\shell\SvnScope'
)

foreach ($registryPath in $registryPaths) {
    if (Test-Path -Path $registryPath) {
        Remove-Item -Path $registryPath -Recurse -Force
    }
}

Write-Host 'SVN Scope context menu removed for the current user.' -ForegroundColor Green
Write-Host 'You can now delete the portable folder.'

$exePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'SVN Scope.exe'))
$shortcutShell = New-Object -ComObject WScript.Shell
foreach ($folderName in @('DesktopDirectory', 'Programs')) {
    $shortcutPath = Join-Path ([Environment]::GetFolderPath($folderName)) 'SVN Scope.lnk'
    if (Test-Path -LiteralPath $shortcutPath) {
        $shortcut = $shortcutShell.CreateShortcut($shortcutPath)
        if ($shortcut.TargetPath -eq $exePath) {
            Remove-Item -LiteralPath $shortcutPath -Force
        }
    }
}

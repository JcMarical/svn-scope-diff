# Select the same registration scope for install, upgrade and uninstall
function Get-SvnScopeRegistryRoots {
    param([switch]$AllUsers)

    $machineRoot = 'HKLM:\Software\Classes'
    $hasMachineEntry = @(Get-SvnScopeRegistryEntries $machineRoot).Count -gt 0
    if ($AllUsers -or $hasMachineEntry) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'The machine-wide SVN Scope menu requires an administrator terminal. Run this script as administrator; the existing menu has not been changed.'
        }
    }

    'HKCU:\Software\Classes'
    if ($AllUsers -or $hasMachineEntry) {
        $machineRoot
    }
}

# A moved executable needs a new verb because running Explorer processes cache commands
function Get-SvnScopeVerbName {
    param([string]$ExecutablePath)

    $normalizedPath = [IO.Path]::GetFullPath($ExecutablePath).ToUpperInvariant()
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalizedPath))
        return 'SvnScope.Open.' + [BitConverter]::ToString($hash).Replace('-', '').Substring(0, 16)
    } finally {
        $algorithm.Dispose()
    }
}

# Only enumerate this application's legacy and path-specific entries
function Get-SvnScopeRegistryEntries {
    param([string]$RegistryRoot)

    foreach ($shellPath in @('Directory\shell', 'Directory\Background\shell')) {
        Get-ChildItem -LiteralPath "$RegistryRoot\$shellPath" -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -eq 'SvnScope' -or $_.PSChildName -match '^SvnScope\.Open\.[0-9A-F]{16}$' } |
            ForEach-Object { $_.PSPath }
    }
}

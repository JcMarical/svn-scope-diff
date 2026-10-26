$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\portable\ContextMenu-Registry.ps1')

function Assert-Equal($Actual, $Expected) {
    if (($Actual -join '|') -ne ($Expected -join '|')) {
        throw "Expected [$Expected], got [$Actual]"
    }
}

# Scope selection uses no writes to the machine registry
$script:existingMachinePath = ''
$script:isAdministrator = $true
$entriesFunction = ${function:Get-SvnScopeRegistryEntries}
function Get-SvnScopeRegistryEntries {
    param([string]$Path)
    if ($Path -eq 'HKLM:\Software\Classes' -and $script:existingMachinePath) { $script:existingMachinePath }
}
function New-Object {
    param([string]$TypeName)
    $principal = [pscustomobject]@{}
    $principal | Add-Member ScriptMethod IsInRole { param($Role) return $script:isAdministrator }
    return $principal
}
try {
    $userRoot = 'HKCU:\Software\Classes'
    $machineRoot = 'HKLM:\Software\Classes'
    Assert-Equal @(Get-SvnScopeRegistryRoots) @($userRoot)
    Assert-Equal @(Get-SvnScopeRegistryRoots -AllUsers) @($userRoot, $machineRoot)
    foreach ($suffix in @('Directory\shell\SvnScope', 'Directory\Background\shell\SvnScope')) {
        $script:existingMachinePath = "$machineRoot\$suffix"
        Assert-Equal @(Get-SvnScopeRegistryRoots) @($userRoot, $machineRoot)
    }
    $script:isAdministrator = $false
    $didFail = $false
    try { Get-SvnScopeRegistryRoots | Out-Null }
    catch { $didFail = $_.Exception.Message -like '*administrator terminal*' }
    Assert-Equal $didFail $true
    $script:existingMachinePath = ''
    Assert-Equal @(Get-SvnScopeRegistryRoots) @($userRoot)
    $didFail = $false
    try { Get-SvnScopeRegistryRoots -AllUsers | Out-Null }
    catch { $didFail = $_.Exception.Message -like '*administrator terminal*' }
    Assert-Equal $didFail $true
} finally {
    Set-Item Function:\Get-SvnScopeRegistryEntries $entriesFunction
    Remove-Item Function:\New-Object
}

# Exercise the real writer in an isolated current-user test key
$scriptPath = Join-Path $PSScriptRoot '..\portable\Register-ContextMenu.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors -join '; ') }
$writer = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Set-SvnScopeContextEntry' }, $true)
Invoke-Expression $writer.Extent.Text
$testRoot = 'HKCU:\Software\SvnScopeContextMenuTests\' + [Guid]::NewGuid().ToString('N')
Assert-Equal (Get-SvnScopeVerbName 'C:\One\SVN Scope.exe') (Get-SvnScopeVerbName 'c:\one\svn scope.exe')
if ((Get-SvnScopeVerbName 'C:\One\SVN Scope.exe') -eq (Get-SvnScopeVerbName 'C:\Two\SVN Scope.exe')) { throw 'Moved executable reused a cached verb' }
$menuText = 'SVN Scope test'
$exePath = 'C:\Test Folder\SVN Scope.exe'
try {
    foreach ($placeholder in @('%1', '%V')) {
        $entryPath = "$testRoot\$placeholder"
        Set-SvnScopeContextEntry $entryPath $placeholder
        Assert-Equal (Get-Item "$entryPath\command").GetValue('') ('"' + $exePath + '" "' + $placeholder + '"')
        Set-ItemProperty $entryPath -Name TestSentinel -Value 'keep'
        $oldHandle = Get-Item "$entryPath\command"
        $exePath = 'C:\New Folder\SVN Scope.exe'
        Set-SvnScopeContextEntry $entryPath $placeholder
        Assert-Equal $oldHandle.GetValue('') ('"' + $exePath + '" "' + $placeholder + '"')
        Assert-Equal (Get-ItemPropertyValue $entryPath -Name TestSentinel) 'keep'
        $oldHandle.Close()
    }
    $verbName = Get-SvnScopeVerbName $exePath
    foreach ($shellPath in @('Directory\shell', 'Directory\Background\shell')) {
        foreach ($entryName in @('SvnScope', $verbName, 'SvnScopeOtherApp')) {
            New-Item -Path "$testRoot\$shellPath\$entryName" -Force | Out-Null
        }
    }
    $entries = @(Get-SvnScopeRegistryEntries $testRoot)
    Assert-Equal $entries.Count 4
    if ($entries -match 'SvnScopeOtherApp') { throw 'Unrelated menu included in cleanup' }
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
Write-Host 'Context-menu scope, permission preflight, quoting and in-place update tests passed.'

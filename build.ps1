[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot 'out')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleName = 'SurfaceWinPEDrivers'
$modulePath = Join-Path $OutputPath $moduleName

if (Test-Path -LiteralPath $modulePath) {
    Remove-Item -LiteralPath $modulePath -Recurse -Force
}
New-Item -ItemType Directory -Path $modulePath -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'SurfaceWinPEDrivers.psd1') -Destination $modulePath
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'SurfaceWinPEDrivers.psm1') -Destination $modulePath
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Private') -Destination $modulePath -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Public') -Destination $modulePath -Recurse

foreach ($optionalFile in @('README.md','LICENSE')) {
    $source = Join-Path $PSScriptRoot $optionalFile
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination $modulePath
    }
}

$manifestPath = Join-Path $modulePath 'SurfaceWinPEDrivers.psd1'
$manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop

[pscustomobject]@{
    ModuleName    = $manifest.Name
    ModuleVersion = $manifest.Version.ToString()
    Path          = $modulePath
}

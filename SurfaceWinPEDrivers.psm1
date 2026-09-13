Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try { Add-Type -AssemblyName System.Net.Http -ErrorAction Stop } catch {}

$script:WinPEDocumentationUrl = 'https://learn.microsoft.com/en-us/surface/enable-surface-keyboard-for-windows-pe-deployment'
$script:DriverCatalogUrl       = 'https://learn.microsoft.com/en-us/surface/manage-surface-driver-and-firmware-updates'

$privateScripts = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -File | Sort-Object Name
$publicScripts  = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Public')  -Filter '*.ps1' -File | Sort-Object Name

foreach ($scriptFile in @($privateScripts) + @($publicScripts)) {
    . $scriptFile.FullName
}

Update-TypeData -TypeName 'SurfaceWinPEDrivers.Model' -DefaultDisplayPropertySet @(
    'Model', 'Architecture', 'ImportFolderCount', 'RequiredPackageCount', 'DownloadModel', 'Status'
) -Force

Update-TypeData -TypeName 'SurfaceWinPEDrivers.Result' -DefaultDisplayPropertySet @(
    'Model', 'Architecture', 'DriverPackVersion', 'OsBuildNumber', 'Status', 'Path'
) -Force

Export-ModuleMember -Function @(
    'Get-SurfaceWinPEModel',
    'New-SurfaceWinPEManifest',
    'Save-SurfaceWinPEDriver'
)

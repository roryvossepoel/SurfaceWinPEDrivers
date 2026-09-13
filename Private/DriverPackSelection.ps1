# Driver-pack selection is intentionally isolated from the Download Center parser.
# SurfaceWinPEDrivers uses Surface MSI packages only as a source for Windows PE drivers.
# Older Surface models can therefore legitimately expose a Win10-named MSI while still
# being present in Microsoft's current Windows PE deployment guidance.
function Get-SurfaceLatestDriverPack {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$DownloadCenterId,
        [Parameter(Mandatory)][string]$DefaultCpuVendor,
        [Parameter(Mandatory)][string]$DefaultArchitecture
    )

    $data = Get-SurfaceDownloadCenterData -DownloadCenterId $DownloadCenterId
    $packs = @()

    foreach ($file in @($data.Files)) {
        $name = [string]$file.name
        $url  = [string]$file.url

        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($url)) { continue }
        if ($name -notmatch '(?i)\.msi$') { continue }

        # Microsoft publishes both Win10- and Win11-named Surface driver packs. For WinPE
        # we consume only the documented driver folders, so the OS label in the package name
        # is metadata rather than a compatibility gate for the Windows PE image.
        if ($name -notmatch '(?i)_(?<os>Win10|Win11)_(?<build>\d{5})_') { continue }
        $osToken = $Matches.os
        $build = [int]$Matches.build

        if ($name -notmatch '_(?<version>\d+\.\d+\.\d+\.\d+)\.msi$') { continue }
        $version = $Matches.version

        $vendor = $DefaultCpuVendor
        if ($name -match '(?i)_Intel_') { $vendor = 'Intel' }
        elseif ($name -match '(?i)_AMD_') { $vendor = 'AMD' }
        elseif ($name -match '(?i)_ARM(?:64)?(?:_|$)') { $vendor = 'Snapdragon' }

        $architecture = $DefaultArchitecture
        if ($name -match '(?i)_ARM(?:64)?(?:_|$)') { $architecture = 'ARM64' }

        $size = $null
        try {
            if ($file.size) { $size = [int64]([string]$file.size) }
        }
        catch {}

        $publishedDate = Convert-DateTextToIsoUtc ([string]$file.datePublished)

        $packs += [pscustomobject]@{
            DriverPackFileName = $name
            DriverPackVersion  = $version
            OsName             = if ($osToken -ieq 'Win11') { 'Windows 11' } else { 'Windows 10' }
            OsBuildNumber      = $build
            CpuVendor          = $vendor
            CpuArchitecture    = $architecture
            DownloadUrl        = $url
            PublishedDate      = $publishedDate
            FileSizeBytes      = $size
            DetailsUrl         = $data.DetailsUrl
        }
    }

    if ($packs.Count -eq 0) { return $null }

    # The module's goal is the newest Microsoft-published driver source for WinPE.
    # Prefer publication date, then driver-pack version, then OS build as a final tie-breaker.
    return ($packs | Sort-Object `
        @{ Expression = {
            if ($_.PublishedDate) {
                try { [datetime]::Parse([string]$_.PublishedDate, [System.Globalization.CultureInfo]::InvariantCulture) }
                catch { [datetime]::MinValue }
            }
            else { [datetime]::MinValue }
        }; Descending = $true },
        @{ Expression = { [version]$_.DriverPackVersion }; Descending = $true },
        @{ Expression = 'OsBuildNumber'; Descending = $true } |
        Select-Object -First 1)
}

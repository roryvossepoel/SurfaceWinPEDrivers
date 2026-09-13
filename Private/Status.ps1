function Write-SurfaceStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [switch]$Quiet
    )

    if ($Quiet) { return }
    Write-Host ("[SurfaceWinPEDrivers] {0}" -f $Message)
}

function Format-SurfaceFileSize {
    param([AllowNull()][Nullable[Int64]]$Bytes)

    if ($null -eq $Bytes -or $Bytes -lt 0) { return 'size unknown' }
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return ('{0} bytes' -f $Bytes)
}

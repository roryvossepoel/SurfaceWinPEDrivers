function Get-SurfaceWinPEModel {
    <#
    .SYNOPSIS
        Discovers Surface models for which Microsoft publishes Windows PE import guidance.

    .DESCRIPTION
        Reads Microsoft's current Surface Windows PE deployment guidance and Surface driver
        catalog, then matches both sources dynamically. No static model catalog is used.

    .PARAMETER Model
        Optional wildcard filter for the model name.

    .PARAMETER Status
        Optional discovery status filter.

    .EXAMPLE
        Get-SurfaceWinPEModel

    .EXAMPLE
        Get-SurfaceWinPEModel -Model '*Laptop*'

    .EXAMPLE
        Get-SurfaceWinPEModel | Out-GridView -PassThru
    #>
    [CmdletBinding()]
    param(
        [string]$Model,
        [ValidateSet('Matched','Unmatched','Ambiguous')]
        [string]$Status
    )

    $models = @(Get-SurfaceDiscovery)

    if ($Model) {
        $models = @($models | Where-Object Model -Like $Model)
    }
    if ($Status) {
        $models = @($models | Where-Object Status -eq $Status)
    }

    $models | Sort-Object Model
}

function New-SurfaceWinPEManifest {
    <#
    .SYNOPSIS
        Builds a current Surface Windows PE driver manifest without downloading driver packs.

    .DESCRIPTION
        Resolves Microsoft's current Windows PE import guidance against the official Surface
        driver catalog and the newest supported Surface driver pack MSI for each selected model.
        The selected MSI can be Win10- or Win11-named; the OS label is metadata because the
        package is used only as a source for the WinPE driver folders Microsoft documents.

        With -Validate, the cmdlet also verifies the driver-pack and required prerequisite package
        URLs without downloading their contents.

    .PARAMETER All
        Include every model currently published on Microsoft's Surface Windows PE guidance page.

    .PARAMETER Model
        One or more exact Surface model names returned by Get-SurfaceWinPEModel.

    .PARAMETER InputObject
        Surface model objects accepted from the pipeline.

    .PARAMETER Path
        Destination JSON manifest path.

    .PARAMETER Validate
        Test that every model is matched, has Import folders, resolves a supported Surface driver
        pack MSI, and that the driver-pack and required prerequisite package URLs are reachable.
        The manifest is written before a validation error is thrown.

    .EXAMPLE
        New-SurfaceWinPEManifest -All -Path .\SurfaceWinPE.Manifest.json -Validate

    .EXAMPLE
        Get-SurfaceWinPEModel | Out-GridView -PassThru |
            New-SurfaceWinPEManifest -Path .\SurfaceWinPE.Manifest.json -Validate
    #>
    [CmdletBinding(DefaultParameterSetName = 'All')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'All')]
        [switch]$All,

        [Parameter(Mandatory, ParameterSetName = 'Named')]
        [string[]]$Model,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Pipeline')]
        [psobject]$InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [switch]$Validate
    )

    begin {
        $pipelineModels = [System.Collections.Generic.List[object]]::new()
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Pipeline') {
            $pipelineModels.Add($InputObject)
        }
    }

    end {
        $discovered = @(Get-SurfaceDiscovery)

        switch ($PSCmdlet.ParameterSetName) {
            'All' {
                $selected = $discovered
            }
            'Named' {
                $selected = foreach ($name in $Model) {
                    $matches = @($discovered | Where-Object Model -eq $name)
                    if ($matches.Count -eq 0) { throw "Surface model was not found in current Microsoft WinPE guidance: $name" }
                    if ($matches.Count -gt 1) { throw "Surface model name is not unique: $name" }
                    $matches[0]
                }
            }
            'Pipeline' {
                $selected = foreach ($item in $pipelineModels) {
                    if ($item.PSObject.Properties['Model']) {
                        $matches = @($discovered | Where-Object Model -eq ([string]$item.Model))
                        if ($matches.Count -eq 1) { $matches[0]; continue }
                    }
                    throw 'Pipeline input must be an object returned by Get-SurfaceWinPEModel.'
                }
            }
        }

        $urlValidationCache = @{}
        $manifestModels = @()
        $failureCount = 0

        foreach ($surface in @($selected)) {
            Write-Verbose "Resolving $($surface.Model)"
            $errors = [System.Collections.Generic.List[string]]::new()
            $driverPack = $null
            $driverValidation = $null
            $requiredPackageValidation = @()

            if ($surface.Status -ne 'Matched') {
                $errors.Add("Discovery status is $($surface.Status).")
            }
            if (@($surface.ImportFolders).Count -eq 0) {
                $errors.Add('Microsoft WinPE guidance did not contain any Import folders.')
            }

            foreach ($package in @($surface.RequiredPackages)) {
                if (-not $package.DownloadUrl) {
                    $errors.Add("Required prerequisite package '$($package.Folder)' has no download URL.")
                }
            }

            if ($surface.Status -eq 'Matched') {
                try {
                    $driverPack = Get-SurfaceLatestDriverPack `
                        -DownloadCenterId $surface.DownloadCenterId `
                        -DefaultCpuVendor $surface.CpuVendor `
                        -DefaultArchitecture $surface.Architecture

                    if (-not $driverPack) {
                        $errors.Add('No supported Surface driver pack MSI was found on the Microsoft Download Center page.')
                    }
                }
                catch {
                    $errors.Add("Failed to resolve Download Center metadata: $($_.Exception.Message)")
                }
            }

            if ($Validate -and $driverPack) {
                if (-not $urlValidationCache.ContainsKey($driverPack.DownloadUrl)) {
                    $urlValidationCache[$driverPack.DownloadUrl] = Test-SurfaceUri -Uri $driverPack.DownloadUrl
                }
                $driverValidation = $urlValidationCache[$driverPack.DownloadUrl]
                if (-not $driverValidation.Success) {
                    $errors.Add("Driver pack URL validation failed: $($driverPack.DownloadUrl)")
                }
            }

            foreach ($package in @($surface.RequiredPackages)) {
                $validation = $null
                if ($Validate -and $package.DownloadUrl) {
                    if (-not $urlValidationCache.ContainsKey($package.DownloadUrl)) {
                        $urlValidationCache[$package.DownloadUrl] = Test-SurfaceUri -Uri $package.DownloadUrl
                    }
                    $validation = $urlValidationCache[$package.DownloadUrl]
                    if (-not $validation.Success) {
                        $errors.Add("Required package URL validation failed for '$($package.Folder)': $($package.DownloadUrl)")
                    }
                }

                $requiredPackageValidation += [pscustomobject]@{
                    Name          = $package.Name
                    Folder        = $package.Folder
                    DownloadUrl   = $package.DownloadUrl
                    ArchiveType   = $package.ArchiveType
                    Required      = $true
                    UrlValidation = $validation
                }
            }

            $configurationHash = Get-SurfaceConfigurationHash `
                -ImportFolders @($surface.ImportFolders) `
                -RequiredPackages @($surface.RequiredPackages)

            $entryStatus = if ($errors.Count -eq 0) { 'Ready' } else { 'Failed' }
            if ($entryStatus -eq 'Failed') { $failureCount++ }

            $manifestModels += [pscustomobject]@{
                Manufacturer     = 'Microsoft'
                Model            = $surface.Model
                Architecture     = $surface.Architecture
                CpuVendor        = $surface.CpuVendor
                DiscoveryStatus  = $surface.Status
                DownloadModel    = $surface.DownloadModel
                DownloadCenterId = $surface.DownloadCenterId
                DetailsUrl       = $surface.DetailsUrl
                WinPE            = [pscustomobject]@{
                    ImportFolders       = @($surface.ImportFolders)
                    ImportFolderSource  = $surface.ImportFolderSource
                    RequiredPackages    = @($requiredPackageValidation)
                    ConfigurationHash   = $configurationHash
                }
                DriverPack       = $driverPack
                Validation       = [pscustomobject]@{
                    Status               = $entryStatus
                    Errors               = @($errors)
                    DriverPackUrl        = $driverValidation
                    ImportFolderCount    = @($surface.ImportFolders).Count
                    RequiredPackageCount = @($surface.RequiredPackages).Count
                }
            }
        }

        # Also record official Surface download entries that do not currently have a WinPE recipe.
        # These are not errors, but make changes on either Microsoft source visible in a dry run.
        $downloadCatalog = @(Get-SurfaceDriverDownloadCatalog)
        $winpeKeys = @($discovered | ForEach-Object ModelKey)
        $driverOnly = @(
            $downloadCatalog |
                Where-Object { $_.ModelKey -notin $winpeKeys } |
                Select-Object Model, DownloadCenterId, DetailsUrl
        )

        $manifest = [pscustomobject]@{
            SchemaVersion  = 2
            GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            Sources        = [pscustomobject]@{
                WinPEGuidance = $script:WinPEDocumentationUrl
                DriverCatalog = $script:DriverCatalogUrl
            }
            Discovery      = [pscustomobject]@{
                WinPEModelCount        = $discovered.Count
                SelectedModelCount     = @($selected).Count
                MatchedCount           = @($discovered | Where-Object Status -eq 'Matched').Count
                UnmatchedCount         = @($discovered | Where-Object Status -eq 'Unmatched').Count
                AmbiguousCount         = @($discovered | Where-Object Status -eq 'Ambiguous').Count
                DriverCatalogOnly      = $driverOnly
                DriverCatalogOnlyCount = $driverOnly.Count
            }
            Validation     = [pscustomobject]@{
                Performed    = [bool]$Validate
                FailureCount = $failureCount
                Status       = if ($failureCount -eq 0) { 'Passed' } else { 'Failed' }
            }
            Models         = $manifestModels
        }

        $parent = Split-Path -Parent $Path
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8

        Write-Verbose "Manifest written to $Path"
        Write-Output $manifest

        if ($Validate -and $failureCount -gt 0) {
            throw "Surface WinPE manifest validation failed for $failureCount model(s). The manifest was written to '$Path' with details."
        }
    }
}

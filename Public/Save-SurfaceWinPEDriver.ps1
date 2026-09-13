function Save-SurfaceWinPEDriver {
    <#
    .SYNOPSIS
        Downloads and extracts the required Windows PE drivers for selected Surface models.

    .DESCRIPTION
        Dynamically resolves the selected Surface models against Microsoft's current guidance,
        downloads the newest Windows 11 Surface driver pack, extracts the MSI, copies only the
        published WinPE Import folders, and adds any required prerequisite packages such as
        SurfaceHidMini_WinPE_Intel or SurfaceHidMini_WinPE_ARM.

        Only the final WinPE driver folders are kept in the output path. MSI and extraction data
        are stored in a temporary working directory and removed after the model has been built.

    .PARAMETER Model
        One or more exact model names returned by Get-SurfaceWinPEModel.

    .PARAMETER InputObject
        Surface model objects accepted from the pipeline.

    .PARAMETER Path
        Root output directory. Each selected Surface model receives its own subfolder.

    .PARAMETER Force
        Rebuild the output even when the current model folder already matches the latest driver
        pack version and current Microsoft WinPE configuration.

    .EXAMPLE
        Save-SurfaceWinPEDriver -Model 'Surface Laptop 8 - Intel' -Path 'C:\WinPE\Surface'

    .EXAMPLE
        Get-SurfaceWinPEModel |
            Out-GridView -Title 'Select Surface models' -PassThru |
            Save-SurfaceWinPEDriver -Path 'C:\WinPE\Surface'
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Named')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Named')]
        [string[]]$Model,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Pipeline')]
        [psobject]$InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [switch]$Force
    )

    begin {
        if (-not (Test-SurfaceWindowsPlatform)) {
            throw 'Save-SurfaceWinPEDriver requires Windows because Surface MSI packages are extracted with msiexec.exe.'
        }
        $pipelineModels = [System.Collections.Generic.List[object]]::new()
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Pipeline') {
            $pipelineModels.Add($InputObject)
        }
    }

    end {
        $discovered = @(Get-SurfaceDiscovery)
        $selected = @()

        if ($PSCmdlet.ParameterSetName -eq 'Named') {
            foreach ($name in $Model) {
                $matches = @($discovered | Where-Object Model -eq $name)
                if ($matches.Count -eq 0) { throw "Surface model was not found in current Microsoft WinPE guidance: $name" }
                if ($matches.Count -gt 1) { throw "Surface model name is not unique: $name" }
                $selected += $matches[0]
            }
        }
        else {
            foreach ($item in $pipelineModels) {
                if (-not $item.PSObject.Properties['Model']) {
                    throw 'Pipeline input must be an object returned by Get-SurfaceWinPEModel.'
                }
                $matches = @($discovered | Where-Object Model -eq ([string]$item.Model))
                if ($matches.Count -ne 1) {
                    throw "Could not uniquely resolve pipeline model '$($item.Model)' against current Microsoft guidance."
                }
                $selected += $matches[0]
            }
        }

        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }

        foreach ($surface in $selected) {
            if ($surface.Status -ne 'Matched') {
                throw "Cannot download '$($surface.Model)': discovery status is $($surface.Status)."
            }
            if (@($surface.ImportFolders).Count -eq 0) {
                throw "Cannot download '$($surface.Model)': Microsoft WinPE guidance returned no Import folders."
            }
            foreach ($package in @($surface.RequiredPackages)) {
                if (-not $package.DownloadUrl) {
                    throw "Cannot download '$($surface.Model)': required package '$($package.Folder)' has no download URL."
                }
            }

            Write-Verbose "Resolving latest driver pack for $($surface.Model)"
            $driverPack = Get-SurfaceLatestDriverPack `
                -DownloadCenterId $surface.DownloadCenterId `
                -DefaultCpuVendor $surface.CpuVendor `
                -DefaultArchitecture $surface.Architecture

            if (-not $driverPack) {
                throw "No Windows 11 driver pack was found for '$($surface.Model)'."
            }

            $configurationHash = Get-SurfaceConfigurationHash `
                -ImportFolders @($surface.ImportFolders) `
                -RequiredPackages @($surface.RequiredPackages)

            $modelFolderName = ConvertTo-SurfaceSafePathPart $surface.Model
            $modelPath = Join-Path $Path $modelFolderName
            $metadata = Get-SurfaceOutputMetadata -ModelPath $modelPath

            if (-not $Force -and $metadata -and
                $metadata.DriverPackVersion -eq $driverPack.DriverPackVersion -and
                $metadata.ConfigurationHash -eq $configurationHash) {

                $result = [pscustomobject]@{
                    PSTypeName       = 'SurfaceWinPEDrivers.Result'
                    Model            = $surface.Model
                    Architecture     = $surface.Architecture
                    DriverPackVersion = $driverPack.DriverPackVersion
                    OsBuildNumber    = $driverPack.OsBuildNumber
                    Status           = 'Current'
                    Path             = $modelPath
                }
                $result.PSObject.TypeNames.Insert(0, 'SurfaceWinPEDrivers.Result')
                Write-Output $result
                continue
            }

            if (-not $PSCmdlet.ShouldProcess($surface.Model, "Download and build WinPE drivers in '$modelPath'")) {
                continue
            }

            $workingPath = Join-Path ([IO.Path]::GetTempPath()) ('SurfaceWinPEDrivers-' + [guid]::NewGuid().ToString('N'))
            $msiPath = Join-Path $workingPath $driverPack.DriverPackFileName
            $extractPath = Join-Path $workingPath 'extracted'
            $stagePath = Join-Path $workingPath 'output'

            try {
                New-Item -ItemType Directory -Path $workingPath -Force | Out-Null
                New-Item -ItemType Directory -Path $stagePath -Force | Out-Null

                Write-Verbose "Downloading $($driverPack.DriverPackFileName)"
                Save-SurfaceRemoteFile -Uri $driverPack.DownloadUrl -Path $msiPath

                Write-Verbose "Extracting $($driverPack.DriverPackFileName)"
                Expand-SurfaceMsi -MsiPath $msiPath -DestinationPath $extractPath

                $resolvedFolders = @{}
                $missingFolders = [System.Collections.Generic.List[string]]::new()
                foreach ($folderName in @($surface.ImportFolders)) {
                    $resolved = Resolve-SurfaceExtractedFolder -ExtractedPath $extractPath -FolderName $folderName
                    if ($resolved) { $resolvedFolders[$folderName] = $resolved }
                    else { $missingFolders.Add($folderName) }
                }

                if ($missingFolders.Count -gt 0) {
                    throw "The latest Surface MSI does not contain all WinPE Import folders published by Microsoft for '$($surface.Model)'. Missing: $($missingFolders -join ', ')"
                }

                foreach ($folderName in @($surface.ImportFolders)) {
                    Copy-SurfaceWinPEFolder -SourcePath $resolvedFolders[$folderName] -DestinationRoot $stagePath
                }

                foreach ($package in @($surface.RequiredPackages)) {
                    Write-Verbose "Adding required prerequisite $($package.Folder)"
                    Add-SurfaceRequiredPackage -Package $package -WorkingPath $workingPath -DestinationRoot $stagePath
                }

                $outputMetadata = [pscustomobject]@{
                    SchemaVersion      = 1
                    GeneratedAtUtc     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                    Model              = $surface.Model
                    Architecture       = $surface.Architecture
                    DownloadCenterId   = $surface.DownloadCenterId
                    DriverPackFileName = $driverPack.DriverPackFileName
                    DriverPackVersion  = $driverPack.DriverPackVersion
                    OsBuildNumber      = $driverPack.OsBuildNumber
                    ConfigurationHash  = $configurationHash
                    ImportFolders      = @($surface.ImportFolders)
                    RequiredPackages   = @($surface.RequiredPackages | Select-Object Name, Folder, DownloadUrl, ArchiveType)
                    Sources            = [pscustomobject]@{
                        WinPEGuidance = $script:WinPEDocumentationUrl
                        DriverCatalog = $script:DriverCatalogUrl
                        DriverPack    = $driverPack.DetailsUrl
                    }
                }
                $outputMetadata | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $stagePath '.surfacewinpe.json') -Encoding UTF8

                if (Test-Path -LiteralPath $modelPath) {
                    Remove-Item -LiteralPath $modelPath -Recurse -Force
                }
                Move-Item -LiteralPath $stagePath -Destination $modelPath

                $result = [pscustomobject]@{
                    PSTypeName        = 'SurfaceWinPEDrivers.Result'
                    Model             = $surface.Model
                    Architecture      = $surface.Architecture
                    DriverPackVersion = $driverPack.DriverPackVersion
                    OsBuildNumber     = $driverPack.OsBuildNumber
                    Status            = 'Saved'
                    Path              = $modelPath
                }
                $result.PSObject.TypeNames.Insert(0, 'SurfaceWinPEDrivers.Result')
                Write-Output $result
            }
            finally {
                if (Test-Path -LiteralPath $workingPath) {
                    Remove-Item -LiteralPath $workingPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

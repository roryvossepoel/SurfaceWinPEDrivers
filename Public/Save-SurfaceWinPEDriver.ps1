function Save-SurfaceWinPEDriver {
    <#
    .SYNOPSIS
        Downloads and extracts the required Windows PE drivers for selected Surface models.

    .DESCRIPTION
        Dynamically resolves the selected Surface models against Microsoft's current guidance,
        downloads the newest Windows 11 Surface driver pack, extracts the MSI, copies the
        published WinPE Import folders that are present, and adds any required prerequisite
        packages such as SurfaceHidMini_WinPE_Intel or SurfaceHidMini_WinPE_ARM.

        Microsoft Learn guidance and the currently published Surface MSI can occasionally be
        temporarily out of sync. When Learn lists an Import folder that is not present in the
        current MSI, the cmdlet emits a warning, records the mismatch in the output metadata,
        and continues with the published folders that are present. Required prerequisite packages
        remain mandatory and still cause the build to fail when they cannot be resolved.

        Only the final WinPE driver folders are kept in the output path. MSI and extraction data
        are stored in a temporary working directory. The working directory is removed after a
        successful build and preserved on failure for troubleshooting.

        Major processing stages are shown by default. Use -Quiet to suppress these status messages.

    .PARAMETER Model
        One or more exact model names returned by Get-SurfaceWinPEModel.

    .PARAMETER InputObject
        Surface model objects accepted from the pipeline.

    .PARAMETER Path
        Root output directory. Each selected Surface model receives its own subfolder.

    .PARAMETER Force
        Rebuild the output even when the current model folder already matches the latest driver
        pack version and current Microsoft WinPE configuration.

    .PARAMETER Quiet
        Suppress user-facing processing status messages. Warnings and result objects are still returned.

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

        [switch]$Force,

        [switch]$Quiet
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
        Write-SurfaceStatus -Message 'Reading current Microsoft Surface WinPE guidance and driver catalog...' -Quiet:$Quiet
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

        $modelIndex = 0
        foreach ($surface in $selected) {
            $modelIndex++
            $prefix = '[{0}/{1}] {2}' -f $modelIndex, $selected.Count, $surface.Model

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

            Write-SurfaceStatus -Message "$prefix - Resolving latest Microsoft driver pack..." -Quiet:$Quiet
            $driverPack = Get-SurfaceLatestDriverPack `
                -DownloadCenterId $surface.DownloadCenterId `
                -DefaultCpuVendor $surface.CpuVendor `
                -DefaultArchitecture $surface.Architecture

            if (-not $driverPack) {
                throw "No Windows 11 driver pack was found for '$($surface.Model)'."
            }

            $packSize = Format-SurfaceFileSize -Bytes $driverPack.FileSizeBytes
            Write-SurfaceStatus -Message "$prefix - Driver pack $($driverPack.DriverPackVersion) selected ($packSize)." -Quiet:$Quiet
            Write-SurfaceStatus -Message "$prefix - Microsoft WinPE recipe contains $(@($surface.ImportFolders).Count) import folder(s) and $(@($surface.RequiredPackages).Count) prerequisite package(s)." -Quiet:$Quiet

            $configurationHash = Get-SurfaceConfigurationHash `
                -ImportFolders @($surface.ImportFolders) `
                -RequiredPackages @($surface.RequiredPackages)

            $modelFolderName = ConvertTo-SurfaceSafePathPart $surface.Model
            $modelPath = Join-Path $Path $modelFolderName
            $metadata = Get-SurfaceOutputMetadata -ModelPath $modelPath

            if (-not $Force -and $metadata -and
                $metadata.DriverPackVersion -eq $driverPack.DriverPackVersion -and
                $metadata.ConfigurationHash -eq $configurationHash) {

                $existingMissingFolders = @()
                if ($metadata.PSObject.Properties['MissingImportFolders']) {
                    $existingMissingFolders = @($metadata.MissingImportFolders)
                }

                if ($existingMissingFolders.Count -gt 0) {
                    Write-Warning ("[{0}] Output is current, but Microsoft Learn lists Import folder(s) that are not present in the current Surface MSI: {1}. This indicates that the Learn guidance and published driver pack are not fully synchronized. The missing folders were skipped when this output was built." -f $surface.Model, ($existingMissingFolders -join ', '))
                    Write-SurfaceStatus -Message "$prefix - Output is already current with $($existingMissingFolders.Count) guidance warning(s). No download or rebuild required." -Quiet:$Quiet
                    $currentStatus = 'CurrentWithWarnings'
                }
                else {
                    Write-SurfaceStatus -Message "$prefix - Output is already current. No download or rebuild required." -Quiet:$Quiet
                    $currentStatus = 'Current'
                }

                $result = [pscustomobject]@{
                    PSTypeName        = 'SurfaceWinPEDrivers.Result'
                    Model             = $surface.Model
                    Architecture      = $surface.Architecture
                    DriverPackVersion = $driverPack.DriverPackVersion
                    OsBuildNumber     = $driverPack.OsBuildNumber
                    Status            = $currentStatus
                    Path              = $modelPath
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
            $buildSucceeded = $false

            try {
                New-Item -ItemType Directory -Path $workingPath -Force | Out-Null
                New-Item -ItemType Directory -Path $stagePath -Force | Out-Null

                Write-SurfaceStatus -Message "$prefix - Downloading $($driverPack.DriverPackFileName) ($packSize)..." -Quiet:$Quiet
                Save-SurfaceRemoteFile -Uri $driverPack.DownloadUrl -Path $msiPath
                Write-SurfaceStatus -Message "$prefix - Driver pack download completed." -Quiet:$Quiet

                Write-SurfaceStatus -Message "$prefix - Extracting Surface MSI..." -Quiet:$Quiet
                Expand-SurfaceMsi -MsiPath $msiPath -DestinationPath $extractPath
                Write-SurfaceStatus -Message "$prefix - MSI extraction completed." -Quiet:$Quiet

                Write-SurfaceStatus -Message "$prefix - Validating $(@($surface.ImportFolders).Count) published WinPE import folder(s)..." -Quiet:$Quiet
                $resolvedFolders = @{}
                $missingFolders = [System.Collections.Generic.List[string]]::new()
                foreach ($folderName in @($surface.ImportFolders)) {
                    $resolved = Resolve-SurfaceExtractedFolder -ExtractedPath $extractPath -FolderName $folderName
                    if ($resolved) { $resolvedFolders[$folderName] = $resolved }
                    else { $missingFolders.Add($folderName) }
                }

                if ($resolvedFolders.Count -eq 0) {
                    throw "None of the WinPE Import folders published by Microsoft for '$($surface.Model)' were found in the current Surface MSI."
                }

                $buildWarnings = [System.Collections.Generic.List[object]]::new()
                if ($missingFolders.Count -gt 0) {
                    $missingText = $missingFolders -join ', '
                    $warningMessage = "Microsoft Learn lists the following WinPE Import folder(s) for '$($surface.Model)', but they are not present in the currently published Surface MSI $($driverPack.DriverPackVersion): $missingText. Microsoft Learn guidance and Surface driver packs can temporarily be out of sync. These folders will be skipped and the build will continue with the published folders that are present. Required prerequisite packages remain mandatory."
                    Write-Warning $warningMessage
                    $buildWarnings.Add([pscustomobject]@{
                        Type    = 'MicrosoftGuidanceMismatch'
                        Message = $warningMessage
                    })
                    Write-SurfaceStatus -Message "$prefix - Continuing with $($resolvedFolders.Count) of $(@($surface.ImportFolders).Count) published import folder(s)." -Quiet:$Quiet
                }
                else {
                    Write-SurfaceStatus -Message "$prefix - All published WinPE import folders were found." -Quiet:$Quiet
                }

                Write-SurfaceStatus -Message "$prefix - Copying selected WinPE driver folders..." -Quiet:$Quiet
                foreach ($folderName in @($surface.ImportFolders)) {
                    if ($resolvedFolders.ContainsKey($folderName)) {
                        Copy-SurfaceWinPEFolder -SourcePath $resolvedFolders[$folderName] -DestinationRoot $stagePath
                    }
                }

                foreach ($package in @($surface.RequiredPackages)) {
                    Write-SurfaceStatus -Message "$prefix - Downloading and adding prerequisite: $($package.Folder)..." -Quiet:$Quiet
                    Add-SurfaceRequiredPackage -Package $package -WorkingPath $workingPath -DestinationRoot $stagePath
                    Write-SurfaceStatus -Message "$prefix - Prerequisite added: $($package.Folder)." -Quiet:$Quiet
                }

                Write-SurfaceStatus -Message "$prefix - Writing output metadata..." -Quiet:$Quiet
                $outputMetadata = [pscustomobject]@{
                    SchemaVersion        = 1
                    GeneratedAtUtc       = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                    Model                = $surface.Model
                    Architecture         = $surface.Architecture
                    DownloadCenterId     = $surface.DownloadCenterId
                    DriverPackFileName   = $driverPack.DriverPackFileName
                    DriverPackVersion    = $driverPack.DriverPackVersion
                    OsBuildNumber        = $driverPack.OsBuildNumber
                    ConfigurationHash    = $configurationHash
                    ImportFolders        = @($surface.ImportFolders)
                    MissingImportFolders = @($missingFolders)
                    RequiredPackages     = @($surface.RequiredPackages | Select-Object Name, Folder, DownloadUrl, ArchiveType)
                    Warnings             = @($buildWarnings)
                    Sources              = [pscustomobject]@{
                        WinPEGuidance = $script:WinPEDocumentationUrl
                        DriverCatalog = $script:DriverCatalogUrl
                        DriverPack    = $driverPack.DetailsUrl
                    }
                }
                $outputMetadata | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $stagePath '.surfacewinpe.json') -Encoding UTF8

                Write-SurfaceStatus -Message "$prefix - Publishing completed driver set to '$modelPath'..." -Quiet:$Quiet
                if (Test-Path -LiteralPath $modelPath) {
                    Remove-Item -LiteralPath $modelPath -Recurse -Force
                }
                Move-Item -LiteralPath $stagePath -Destination $modelPath

                $buildSucceeded = $true
                if ($missingFolders.Count -gt 0) {
                    Write-SurfaceStatus -Message "$prefix - Completed with warnings." -Quiet:$Quiet
                    $resultStatus = 'SavedWithWarnings'
                }
                else {
                    Write-SurfaceStatus -Message "$prefix - Completed successfully." -Quiet:$Quiet
                    $resultStatus = 'Saved'
                }

                $result = [pscustomobject]@{
                    PSTypeName        = 'SurfaceWinPEDrivers.Result'
                    Model             = $surface.Model
                    Architecture      = $surface.Architecture
                    DriverPackVersion = $driverPack.DriverPackVersion
                    OsBuildNumber     = $driverPack.OsBuildNumber
                    Status            = $resultStatus
                    Path              = $modelPath
                }
                $result.PSObject.TypeNames.Insert(0, 'SurfaceWinPEDrivers.Result')
                Write-Output $result
            }
            catch {
                Write-SurfaceStatus -Message "$prefix - Build failed. Temporary working directory preserved for troubleshooting: '$workingPath'." -Quiet:$Quiet
                if (Test-Path -LiteralPath $extractPath) {
                    Write-SurfaceStatus -Message "$prefix - Extracted MSI content is available at: '$extractPath'." -Quiet:$Quiet
                }
                throw
            }
            finally {
                if ($buildSucceeded -and (Test-Path -LiteralPath $workingPath)) {
                    Remove-Item -LiteralPath $workingPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

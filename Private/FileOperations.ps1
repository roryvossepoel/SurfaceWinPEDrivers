function Test-SurfaceWindowsPlatform {
    if ($PSVersionTable.PSVersion.Major -ge 6) { return [bool]$IsWindows }
    return ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
}

function ConvertTo-SurfaceSafePathPart {
    param([Parameter(Mandatory)][string]$Name)

    $result = $Name
    foreach ($char in [IO.Path]::GetInvalidFileNameChars()) {
        $result = $result.Replace([string]$char, '_')
    }
    return ($result -replace '\s+', ' ').Trim()
}

function Save-SurfaceRemoteFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Path
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $partial = "$Path.partial"
    Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue

    try {
        if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
            Start-BitsTransfer -Source $Uri -Destination $partial -ErrorAction Stop
        }
        else {
            $params = @{
                Uri         = $Uri
                OutFile     = $partial
                ErrorAction = 'Stop'
                Headers     = @{ 'User-Agent' = 'SurfaceWinPEDrivers/1.0' }
            }
            if ($PSVersionTable.PSVersion.Major -lt 6) { $params.UseBasicParsing = $true }
            Invoke-WebRequest @params
        }

        if (-not (Test-Path -LiteralPath $partial)) { throw "Download did not create '$partial'." }
        if ((Get-Item -LiteralPath $partial).Length -le 0) { throw "Downloaded file is empty: $Uri" }

        Move-Item -LiteralPath $partial -Destination $Path -Force
    }
    finally {
        Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
    }
}

function Expand-SurfaceMsi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MsiPath,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    if (-not (Test-SurfaceWindowsPlatform)) {
        throw 'MSI extraction requires Windows.'
    }

    if (Test-Path -LiteralPath $DestinationPath) {
        Remove-Item -LiteralPath $DestinationPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null

    $logPath = Join-Path $DestinationPath 'msiexec.log'
    $arguments = @(
        '/a', "`"$MsiPath`"",
        "TARGETDIR=`"$DestinationPath`"",
        '/qn',
        '/L*v', "`"$logPath`""
    )

    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "msiexec failed with exit code $($process.ExitCode). Log: $logPath"
    }
}

function Resolve-SurfaceExtractedFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ExtractedPath,
        [Parameter(Mandatory)][string]$FolderName
    )

    $surfaceUpdate = Join-Path (Join-Path $ExtractedPath 'SurfaceUpdate') $FolderName
    if (Test-Path -LiteralPath $surfaceUpdate -PathType Container) { return $surfaceUpdate }

    $matches = @(
        Get-ChildItem -LiteralPath $ExtractedPath -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object Name -ieq $FolderName |
            Select-Object -ExpandProperty FullName
    )

    if ($matches.Count -eq 1) { return $matches[0] }
    if ($matches.Count -eq 0) { return $null }

    throw "Multiple extracted folders named '$FolderName' were found: $($matches -join '; ')"
}

function Copy-SurfaceWinPEFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationRoot
    )

    $name = Split-Path -Leaf $SourcePath
    $destination = Join-Path $DestinationRoot $name
    if (Test-Path -LiteralPath $destination) {
        throw "Duplicate WinPE output folder '$name' would be created."
    }

    Copy-Item -LiteralPath $SourcePath -Destination $DestinationRoot -Recurse -Force
}

function Add-SurfaceRequiredPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Package,
        [Parameter(Mandatory)][string]$WorkingPath,
        [Parameter(Mandatory)][string]$DestinationRoot
    )

    if (-not $Package.DownloadUrl) {
        throw "Required package '$($Package.Folder)' has no download URL."
    }

    $archivePath = Join-Path $WorkingPath ((ConvertTo-SurfaceSafePathPart $Package.Folder) + '.zip')
    $extractPath = Join-Path $WorkingPath ((ConvertTo-SurfaceSafePathPart $Package.Folder) + '-expanded')

    Save-SurfaceRemoteFile -Uri $Package.DownloadUrl -Path $archivePath
    New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force

    $folder = @(
        Get-ChildItem -LiteralPath $extractPath -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object Name -ieq $Package.Folder |
            Select-Object -ExpandProperty FullName
    )

    if ($folder.Count -ne 1) {
        throw "Required package folder '$($Package.Folder)' was expected exactly once in '$archivePath' but $($folder.Count) matches were found."
    }

    Copy-SurfaceWinPEFolder -SourcePath $folder[0] -DestinationRoot $DestinationRoot
}

function Get-SurfaceOutputMetadata {
    param([Parameter(Mandatory)][string]$ModelPath)

    $metadataPath = Join-Path $ModelPath '.surfacewinpe.json'
    if (-not (Test-Path -LiteralPath $metadataPath)) { return $null }

    try { return (Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json) }
    catch { return $null }
}

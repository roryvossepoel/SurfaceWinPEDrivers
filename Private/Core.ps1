function Invoke-SurfaceWebRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [ValidateSet('GET','HEAD')][string]$Method = 'GET',
        [int]$TimeoutSec = 90
    )

    $headers = @{
        'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/153 Safari/537.36 SurfaceWinPEDrivers/1.0'
        'Accept-Language' = 'en-US,en;q=0.9'
    }

    $params = @{
        Uri                = $Uri
        Method             = $Method
        Headers            = $headers
        TimeoutSec         = $TimeoutSec
        MaximumRedirection = 10
        ErrorAction        = 'Stop'
    }

    if ($PSVersionTable.PSVersion.Major -lt 6) {
        $params.UseBasicParsing = $true
    }

    Invoke-WebRequest @params
}

function ConvertFrom-SurfaceHtmlText {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }

    $value = $Text -replace '(?is)<br\s*/?>', "`n"
    $value = $value -replace '(?is)<[^>]+>', ''
    $value = [System.Net.WebUtility]::HtmlDecode($value)
    return $value.Trim()
}

function Get-SurfaceModelKey {
    param([Parameter(Mandatory)][string]$Name)

    $value = [System.Net.WebUtility]::HtmlDecode($Name).Trim()
    $value = $value -replace '[\u2012\u2013\u2014\u2212]', '-'

    # Microsoft sometimes combines the Snapdragon and 5G variants in the WinPE heading,
    # while the download catalog exposes a single cumulative package for the generation.
    if ($value -match '^(?<first>Surface\s+(?:Laptop|Pro)\s+\d+)\s+and\s+Surface\s+.+?\s*-\s*(?<cpu>Intel|AMD|Snapdragon)\s*$') {
        $value = '{0} {1}' -f $Matches.first, $Matches.cpu
    }

    $value = $value -replace '(?i)\bfor\s+business\b', ' '
    $value = $value -replace '(?i)\bwith\s+(intel|amd|snapdragon)\s+processor\b', ' $1 '
    $value = $value -replace '(?i)\((intel|amd|snapdragon)\)', ' $1 '
    $value = $value -replace '(?i)\b(\d+)(?:st|nd|rd|th)\s+edition\b', ' $1 '
    $value = $value -replace '(?i)\b1st\s+gen(?:eration)?\b', ' 1 '
    $value = $value -replace '(?i)\bedition\b', ' '
    $value = $value -replace '(?i)\bprocessor\b', ' '
    $value = $value -replace '(?i)\bwith\b', ' '
    $value = $value -replace '[^A-Za-z0-9]+', ' '
    $value = ($value -replace '\s+', ' ').Trim().ToLowerInvariant()

    if ($value -eq 'surface laptop') { $value = 'surface laptop 1' }

    return $value
}

function Get-SurfaceArchitectureFromName {
    param([Parameter(Mandatory)][string]$Name)

    if ($Name -match '(?i)Snapdragon|\bARM(?:64)?\b') { return 'ARM64' }
    return 'x64'
}

function Get-SurfaceCpuVendorFromName {
    param([Parameter(Mandatory)][string]$Name)

    if ($Name -match '(?i)Snapdragon|\bARM(?:64)?\b') { return 'Snapdragon' }
    if ($Name -match '(?i)\bAMD\b') { return 'AMD' }
    return 'Intel'
}

function Get-SurfaceWinPEImportCatalog {
    [CmdletBinding()]
    param([string]$Uri = $script:WinPEDocumentationUrl)

    $response = Invoke-SurfaceWebRequest -Uri $Uri
    $html = [string]$response.Content

    $sectionPattern = '(?is)<h3\b[^>]*>(?<heading>.*?)</h3>(?<body>.*?)(?=<h3\b|<h2\b|$)'
    $sections = [regex]::Matches($html, $sectionPattern)
    $results = @()

    foreach ($section in $sections) {
        $heading = ConvertFrom-SurfaceHtmlText $section.Groups['heading'].Value
        if ($heading -notmatch '^Surface\s') { continue }

        $body = $section.Groups['body'].Value
        $codeMatch = [regex]::Match($body, '(?is)<pre\b[^>]*>\s*<code\b[^>]*>(?<code>.*?)</code>\s*</pre>')
        if (-not $codeMatch.Success) { continue }

        $code = ConvertFrom-SurfaceHtmlText $codeMatch.Groups['code'].Value
        $folders = @(
            $code -split "`r?`n" |
                ForEach-Object { $_.Trim().Trim('`') } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object {
                    $parts = $_ -split '[\\/]'
                    $parts[-1].Trim()
                } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Select-Object -Unique
        )

        $requiredPackages = @()
        $requiredNames = @(
            [regex]::Matches($body, '(?i)SurfaceHidMini_WinPE_(?:Intel|ARM)') |
                ForEach-Object { $_.Value } |
                Select-Object -Unique
        )

        foreach ($requiredName in $requiredNames) {
            $link = [regex]::Match($body, '(?is)href=["''](?<url>https://download\.microsoft\.com/[^"'']+)["'']')
            if (-not $link.Success) {
                $link = [regex]::Match($html, '(?is)href=["''](?<url>https://download\.microsoft\.com/[^"'']*SurfaceHidMini[^"'']*\.zip[^"'']*)["'']')
            }

            $requiredPackages += [pscustomobject]@{
                Name        = $requiredName
                Folder      = $requiredName
                DownloadUrl = if ($link.Success) { [System.Net.WebUtility]::HtmlDecode($link.Groups['url'].Value) } else { $null }
                ArchiveType = 'Zip'
                Required    = $true
            }
        }

        $results += [pscustomobject]@{
            Model                  = $heading
            ModelKey               = Get-SurfaceModelKey -Name $heading
            Architecture           = Get-SurfaceArchitectureFromName -Name $heading
            CpuVendor              = Get-SurfaceCpuVendorFromName -Name $heading
            ImportFolders          = $folders
            ImportFolderCount      = $folders.Count
            RequiredPackages       = $requiredPackages
            RequiredPackageCount   = $requiredPackages.Count
            SourceUrl              = $Uri
        }
    }

    return $results
}

function Get-SurfaceDriverDownloadCatalog {
    [CmdletBinding()]
    param([string]$Uri = $script:DriverCatalogUrl)

    $response = Invoke-SurfaceWebRequest -Uri $Uri
    $html = [string]$response.Content

    $pattern = '(?is)<a\b[^>]*href=["''](?<url>https://www\.microsoft\.com/[^"'']*?/download/details\.aspx\?id=(?<id>\d+)[^"'']*)["''][^>]*>(?<name>.*?)</a>'
    $matches = [regex]::Matches($html, $pattern)
    $results = @()

    foreach ($match in $matches) {
        $name = ConvertFrom-SurfaceHtmlText $match.Groups['name'].Value
        if ($name -notmatch '^Surface\s') { continue }

        $results += [pscustomobject]@{
            Model            = $name
            ModelKey         = Get-SurfaceModelKey -Name $name
            DownloadCenterId = [int]$match.Groups['id'].Value
            DetailsUrl       = [System.Net.WebUtility]::HtmlDecode($match.Groups['url'].Value)
            Architecture     = Get-SurfaceArchitectureFromName -Name $name
            CpuVendor        = Get-SurfaceCpuVendorFromName -Name $name
            SourceUrl        = $Uri
        }
    }

    return @($results | Sort-Object DownloadCenterId -Unique)
}

function Get-SurfaceDiscovery {
    [CmdletBinding()]
    param()

    $winpe = @(Get-SurfaceWinPEImportCatalog)
    $downloads = @(Get-SurfaceDriverDownloadCatalog)

    foreach ($entry in $winpe) {
        $matches = @($downloads | Where-Object ModelKey -eq $entry.ModelKey)
        $status = if ($matches.Count -eq 1) { 'Matched' } elseif ($matches.Count -eq 0) { 'Unmatched' } else { 'Ambiguous' }
        $match = if ($matches.Count -eq 1) { $matches[0] } else { $null }

        $obj = [pscustomobject]@{
            PSTypeName             = 'SurfaceWinPEDrivers.Model'
            Model                  = $entry.Model
            ModelKey               = $entry.ModelKey
            Architecture           = $entry.Architecture
            CpuVendor              = $entry.CpuVendor
            ImportFolders          = @($entry.ImportFolders)
            ImportFolderCount      = $entry.ImportFolderCount
            RequiredPackages       = @($entry.RequiredPackages)
            RequiredPackageCount   = $entry.RequiredPackageCount
            DownloadModel          = if ($match) { $match.Model } else { $null }
            DownloadCenterId       = if ($match) { $match.DownloadCenterId } else { $null }
            DetailsUrl             = if ($match) { $match.DetailsUrl } else { $null }
            Status                 = $status
            MatchCandidates        = @($matches | ForEach-Object Model)
            WinPESourceUrl         = $entry.SourceUrl
            DriverCatalogSourceUrl = $script:DriverCatalogUrl
        }
        $obj.PSObject.TypeNames.Insert(0, 'SurfaceWinPEDrivers.Model')
        $obj
    }
}

function Convert-DateTextToIsoUtc {
    param([AllowNull()][string]$DateText)
    if ([string]::IsNullOrWhiteSpace($DateText)) { return $null }

    try { $dt = [datetime]::Parse($DateText, [System.Globalization.CultureInfo]::InvariantCulture) }
    catch {
        try { $dt = [datetime]::Parse($DateText) }
        catch { return $null }
    }

    if ($dt.Kind -eq [System.DateTimeKind]::Unspecified) {
        $dt = [datetime]::SpecifyKind($dt, [System.DateTimeKind]::Local)
    }
    return $dt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}

function Get-DlcDetailsObjectFromHtml {
    param([Parameter(Mandatory)][string]$Html)

    $match = [regex]::Match($Html, '(?is)window\.__DLCDetails__\s*=\s*(?<json>\{.*?\})\s*;?\s*</script>')
    if (-not $match.Success) {
        throw 'window.__DLCDetails__ was not found on the Microsoft Download Center page.'
    }

    try { return ($match.Groups['json'].Value | ConvertFrom-Json) }
    catch { throw "Failed to parse Microsoft Download Center metadata: $($_.Exception.Message)" }
}

function Get-SurfaceDownloadCenterData {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$DownloadCenterId)

    $detailsUrl = "https://www.microsoft.com/en-us/download/details.aspx?id=$DownloadCenterId"
    $response = Invoke-SurfaceWebRequest -Uri $detailsUrl
    $dlc = Get-DlcDetailsObjectFromHtml -Html ([string]$response.Content)
    $view = $dlc.dlcDetailsView
    if (-not $view) { throw "dlcDetailsView is missing for Download Center id $DownloadCenterId." }

    [pscustomobject]@{
        DetailsUrl = $detailsUrl
        Files      = @($view.downloadFile)
    }
}

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
        if ($name -notmatch '(?i)_Win11_') { continue }
        if ($name -notmatch '(?i)\.msi$') { continue }
        if ($name -notmatch '_Win11_(?<build>\d{5})_') { continue }
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
        try { if ($file.size) { $size = [int64]([string]$file.size) } } catch {}

        $packs += [pscustomobject]@{
            DriverPackFileName = $name
            DriverPackVersion  = $version
            OsName             = 'Windows 11'
            OsBuildNumber      = $build
            CpuVendor          = $vendor
            CpuArchitecture    = $architecture
            DownloadUrl        = $url
            PublishedDate      = Convert-DateTextToIsoUtc ([string]$file.datePublished)
            FileSizeBytes      = $size
            DetailsUrl         = $data.DetailsUrl
        }
    }

    if ($packs.Count -eq 0) { return $null }

    return ($packs | Sort-Object `
        @{ Expression = 'OsBuildNumber'; Descending = $true },
        @{ Expression = { [version]$_.DriverPackVersion }; Descending = $true } |
        Select-Object -First 1)
}

function Test-SurfaceUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [int]$TimeoutSec = 30
    )

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $true
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [timespan]::FromSeconds($TimeoutSec)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('SurfaceWinPEDrivers/1.0')

    try {
        $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Head, $Uri)
        $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()

        if (-not $response.IsSuccessStatusCode -and [int]$response.StatusCode -in 403,405) {
            $response.Dispose()
            $request.Dispose()
            $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $Uri)
            $request.Headers.Range = [System.Net.Http.Headers.RangeHeaderValue]::new(0, 0)
            $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        }

        [pscustomobject]@{
            Uri           = $Uri
            Success       = [bool]$response.IsSuccessStatusCode
            StatusCode    = [int]$response.StatusCode
            ContentLength = if ($response.Content.Headers.ContentLength) { [int64]$response.Content.Headers.ContentLength } else { $null }
            ContentType   = if ($response.Content.Headers.ContentType) { [string]$response.Content.Headers.ContentType.MediaType } else { $null }
            Error         = $null
        }
    }
    catch {
        [pscustomobject]@{
            Uri           = $Uri
            Success       = $false
            StatusCode    = $null
            ContentLength = $null
            ContentType   = $null
            Error         = $_.Exception.Message
        }
    }
    finally {
        if ($response) { $response.Dispose() }
        if ($request) { $request.Dispose() }
        $client.Dispose()
        $handler.Dispose()
    }
}

function Get-SurfaceConfigurationHash {
    param(
        [Parameter(Mandatory)][string[]]$ImportFolders,
        [object[]]$RequiredPackages = @()
    )

    $packageLines = @($RequiredPackages | ForEach-Object { '{0}|{1}' -f $_.Folder, $_.DownloadUrl })
    $text = (@($ImportFolders | Sort-Object) + @($packageLines | Sort-Object)) -join "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

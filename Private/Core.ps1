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

function Get-SurfaceDiscovery {
    [CmdletBinding()]
    param()

    $winpe = @(Get-SurfaceWinPEImportCatalog)
    $downloads = @(Get-SurfaceDriverDownloadCatalog)

    foreach ($entry in $winpe) {
        $matches = @($downloads | Where-Object ModelKey -eq $entry.ModelKey)
        $status = if ($matches.Count -eq 1) { 'Matched' } elseif ($matches.Count -eq 0) { 'Unmatched' } else { 'Ambiguous' }
        $match = if ($matches.Count -eq 1) { $matches[0] } else { $null }
        $importFolderSource = if ($entry.PSObject.Properties['ImportFolderSource']) {
            [string]$entry.ImportFolderSource
        }
        else {
            'PrimaryImportFolders'
        }

        $obj = [pscustomobject]@{
            PSTypeName             = 'SurfaceWinPEDrivers.Model'
            Model                  = $entry.Model
            ModelKey               = $entry.ModelKey
            Architecture           = $entry.Architecture
            CpuVendor              = $entry.CpuVendor
            ImportFolders          = @($entry.ImportFolders)
            ImportFolderCount      = $entry.ImportFolderCount
            ImportFolderSource     = $importFolderSource
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

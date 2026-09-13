# Source parsers live separately so upstream Microsoft HTML changes can be isolated and tested.
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
            $link = [regex]::Match(
                $body,
                '(?is)href=["''](?<url>https://download\.microsoft\.com/[^"'']*SurfaceHidMini[^"'']*\.zip(?:\?[^"'']*)?)["'']'
            )
            if (-not $link.Success) {
                $link = [regex]::Match(
                    $html,
                    '(?is)href=["''](?<url>https://download\.microsoft\.com/[^"'']*SurfaceHidMini[^"'']*\.zip(?:\?[^"'']*)?)["'']'
                )
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
            Model                = $heading
            ModelKey             = Get-SurfaceModelKey -Name $heading
            Architecture         = Get-SurfaceArchitectureFromName -Name $heading
            CpuVendor            = Get-SurfaceCpuVendorFromName -Name $heading
            ImportFolders        = $folders
            ImportFolderCount    = $folders.Count
            RequiredPackages     = $requiredPackages
            RequiredPackageCount = $requiredPackages.Count
            SourceUrl            = $Uri
        }
    }

    return $results
}

function Get-SurfaceDriverDownloadCatalog {
    [CmdletBinding()]
    param([string]$Uri = $script:DriverCatalogUrl)

    $response = Invoke-SurfaceWebRequest -Uri $Uri
    $results = @()
    $links = @()
    if ($response.PSObject.Properties['Links']) {
        $links = @($response.Links)
    }

    foreach ($link in $links) {
        if (-not $link -or -not $link.PSObject.Properties['href']) { continue }
        $href = [string]$link.PSObject.Properties['href'].Value
        if ([string]::IsNullOrWhiteSpace($href)) { continue }
        $href = [System.Net.WebUtility]::HtmlDecode($href)
        if ($href -notmatch '(?i)download/details\.aspx\?[^#]*\bid=(?<id>\d+)') { continue }
        $downloadCenterId = [int]$Matches.id

        if (-not [uri]::IsWellFormedUriString($href, [UriKind]::Absolute)) {
            $href = ([uri]::new([uri]$Uri, $href)).AbsoluteUri
        }

        $name = ''
        if ($link.PSObject.Properties['innerText']) { $name = [string]$link.PSObject.Properties['innerText'].Value }
        elseif ($link.PSObject.Properties['innerHTML']) { $name = ConvertFrom-SurfaceHtmlText ([string]$link.PSObject.Properties['innerHTML'].Value) }
        elseif ($link.PSObject.Properties['outerHTML']) { $name = ConvertFrom-SurfaceHtmlText ([string]$link.PSObject.Properties['outerHTML'].Value) }
        $name = [System.Net.WebUtility]::HtmlDecode($name).Trim()
        if ($name -notmatch '^Surface\s') { continue }

        $results += [pscustomobject]@{
            Model            = $name
            ModelKey         = Get-SurfaceModelKey -Name $name
            DownloadCenterId = $downloadCenterId
            DetailsUrl       = $href
            Architecture     = Get-SurfaceArchitectureFromName -Name $name
            CpuVendor        = Get-SurfaceCpuVendorFromName -Name $name
            SourceUrl        = $Uri
        }
    }

    $html = [string]$response.Content
    $pattern = '(?is)<a\b[^>]*href=["''](?<url>[^"'']*download/details\.aspx\?[^"'']*\bid=(?<id>\d+)[^"'']*)["''][^>]*>(?<name>.*?)</a>'
    foreach ($match in [regex]::Matches($html, $pattern)) {
        $name = ConvertFrom-SurfaceHtmlText $match.Groups['name'].Value
        if ($name -notmatch '^Surface\s') { continue }

        $href = [System.Net.WebUtility]::HtmlDecode($match.Groups['url'].Value)
        if (-not [uri]::IsWellFormedUriString($href, [UriKind]::Absolute)) {
            $href = ([uri]::new([uri]$Uri, $href)).AbsoluteUri
        }

        $results += [pscustomobject]@{
            Model            = $name
            ModelKey         = Get-SurfaceModelKey -Name $name
            DownloadCenterId = [int]$match.Groups['id'].Value
            DetailsUrl       = $href
            Architecture     = Get-SurfaceArchitectureFromName -Name $name
            CpuVendor        = Get-SurfaceCpuVendorFromName -Name $name
            SourceUrl        = $Uri
        }
    }

    $unique = @{}
    foreach ($result in $results) {
        $key = [string]$result.DownloadCenterId
        if (-not $unique.ContainsKey($key)) { $unique[$key] = $result }
    }

    return @($unique.Values | Sort-Object Model)
}

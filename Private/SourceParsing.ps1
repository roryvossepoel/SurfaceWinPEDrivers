# Overrides source parsers from Core.ps1 with implementations that prefer Invoke-WebRequest's
# parsed link collection and only fall back to raw HTML matching when needed.
function Get-SurfaceDriverDownloadCatalog {
    [CmdletBinding()]
    param([string]$Uri = $script:DriverCatalogUrl)

    $response = Invoke-SurfaceWebRequest -Uri $Uri
    $results = @()

    foreach ($link in @($response.Links)) {
        $href = [string]$link.href
        if ([string]::IsNullOrWhiteSpace($href)) { continue }
        $href = [System.Net.WebUtility]::HtmlDecode($href)
        if ($href -notmatch '(?i)microsoft\.com/.*/?download/details\.aspx\?[^#]*\bid=(?<id>\d+)') { continue }

        $name = ''
        if ($link.PSObject.Properties['innerText']) { $name = [string]$link.innerText }
        elseif ($link.PSObject.Properties['innerHTML']) { $name = ConvertFrom-SurfaceHtmlText ([string]$link.innerHTML) }
        elseif ($link.PSObject.Properties['outerHTML']) { $name = ConvertFrom-SurfaceHtmlText ([string]$link.outerHTML) }
        $name = [System.Net.WebUtility]::HtmlDecode($name).Trim()
        if ($name -notmatch '^Surface\s') { continue }

        $results += [pscustomobject]@{
            Model            = $name
            ModelKey         = Get-SurfaceModelKey -Name $name
            DownloadCenterId = [int]$Matches.id
            DetailsUrl       = $href
            Architecture     = Get-SurfaceArchitectureFromName -Name $name
            CpuVendor        = Get-SurfaceCpuVendorFromName -Name $name
            SourceUrl        = $Uri
        }
    }

    if ($results.Count -eq 0) {
        $html = [string]$response.Content
        $pattern = '(?is)<a\b[^>]*href=["''](?<url>[^"'']*microsoft\.com/[^"'']*download/details\.aspx\?[^"'']*\bid=(?<id>\d+)[^"'']*)["''][^>]*>(?<name>.*?)</a>'
        foreach ($match in [regex]::Matches($html, $pattern)) {
            $name = ConvertFrom-SurfaceHtmlText $match.Groups['name'].Value
            if ($name -notmatch '^Surface\s') { continue }
            $href = [System.Net.WebUtility]::HtmlDecode($match.Groups['url'].Value)

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
    }

    return @($results | Sort-Object DownloadCenterId -Unique)
}

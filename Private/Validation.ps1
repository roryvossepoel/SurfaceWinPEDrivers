# Kept separate from discovery so URL validation can evolve without touching the page parsers.
function Test-SurfaceUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [int]$TimeoutSec = 30
    )

    $handler = $null
    $client = $null
    $request = $null
    $response = $null

    try {
        $handler = [System.Net.Http.HttpClientHandler]::new()
        $handler.AllowAutoRedirect = $true
        $client = [System.Net.Http.HttpClient]::new($handler)
        $client.Timeout = [timespan]::FromSeconds($TimeoutSec)
        $client.DefaultRequestHeaders.UserAgent.ParseAdd('SurfaceWinPEDrivers/1.0')

        $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Head, $Uri)
        $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()

        if (-not $response.IsSuccessStatusCode -and [int]$response.StatusCode -in 403,405) {
            $response.Dispose()
            $response = $null
            $request.Dispose()
            $request = $null

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
        if ($client) { $client.Dispose() }
        if ($handler) { $handler.Dispose() }
    }
}

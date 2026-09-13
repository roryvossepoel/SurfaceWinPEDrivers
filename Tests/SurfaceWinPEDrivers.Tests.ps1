BeforeAll {
    $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'SurfaceWinPEDrivers.psd1'
    Import-Module $modulePath -Force
}

Describe 'SurfaceWinPEDrivers module' {
    It 'exports the expected public commands' {
        $commands = Get-Command -Module SurfaceWinPEDrivers | Select-Object -ExpandProperty Name
        $commands | Should -Contain 'Get-SurfaceWinPEModel'
        $commands | Should -Contain 'New-SurfaceWinPEManifest'
        $commands | Should -Contain 'Save-SurfaceWinPEDriver'
    }

    InModuleScope SurfaceWinPEDrivers {
        It 'normalizes current Intel marketing names to the same key' {
            Get-SurfaceModelKey 'Surface Laptop 8 - Intel' |
                Should -Be (Get-SurfaceModelKey 'Surface Laptop for Business 8th Edition (Intel)')
        }

        It 'normalizes Surface Pro 12 Intel marketing names to the same key' {
            Get-SurfaceModelKey 'Surface Pro 12 - Intel' |
                Should -Be (Get-SurfaceModelKey 'Surface Pro for Business 12th Edition (Intel)')
        }

        It 'normalizes combined Pro 11 Snapdragon heading to the cumulative download entry' {
            Get-SurfaceModelKey 'Surface Pro 11 and Surface Pro 11 5G - Snapdragon' |
                Should -Be (Get-SurfaceModelKey 'Surface Pro 11th Edition (Snapdragon)')
        }

        It 'discovers Import folders and required SurfaceHidMini package from WinPE HTML' {
            $sample = @'
<html><body>
<h3>Surface Laptop 8 - Intel</h3>
<p>In addition to the folders listed here, include <code>SurfaceHidMini_WinPE_Intel</code>
from this <a href="https://download.microsoft.com/example/SurfaceHidMini_WinPE.zip">downloadable zip file</a>.</p>
<p>Import folders</p>
<pre><code>acpiplatformextension
SurfaceUpdate\SerialHub
wifi</code></pre>
<h2>Next</h2>
</body></html>
'@ -replace '\\"','"'
            Mock Invoke-SurfaceWebRequest { [pscustomobject]@{ Content = $sample } }

            $catalog = @(Get-SurfaceWinPEImportCatalog -Uri 'https://example.test/winpe')
            $catalog.Count | Should -Be 1
            ($catalog[0].ImportFolders -join ',') | Should -Be 'acpiplatformextension,SerialHub,wifi'
            $catalog[0].RequiredPackageCount | Should -Be 1
            $catalog[0].RequiredPackages[0].Folder | Should -Be 'SurfaceHidMini_WinPE_Intel'
            $catalog[0].RequiredPackages[0].DownloadUrl | Should -Be 'https://download.microsoft.com/example/SurfaceHidMini_WinPE.zip'
        }

        It 'discovers official Download Center IDs from driver catalog HTML' {
            $sample = @'
<html><body>
<a href="https://www.microsoft.com/en-us/download/details.aspx?id=108669">Surface Laptop for Business 8th Edition (Intel)</a>
<a href="https://www.microsoft.com/en-us/download/details.aspx?id=108671">Surface Pro for Business 12th Edition (Intel)</a>
</body></html>
'@ -replace '\\"','"'
            Mock Invoke-SurfaceWebRequest { [pscustomobject]@{ Content = $sample } }

            $catalog = @(Get-SurfaceDriverDownloadCatalog -Uri 'https://example.test/catalog')
            $catalog.Count | Should -Be 2
            ($catalog | Where-Object DownloadCenterId -eq 108669).Model | Should -Be 'Surface Laptop for Business 8th Edition (Intel)'
        }

        It 'produces a stable configuration hash independent of folder ordering' {
            $a = Get-SurfaceConfigurationHash -ImportFolders @('wifi','serialhub')
            $b = Get-SurfaceConfigurationHash -ImportFolders @('serialhub','wifi')
            $a | Should -Be $b
        }
    }
}

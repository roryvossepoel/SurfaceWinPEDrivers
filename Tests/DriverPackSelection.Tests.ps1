BeforeAll {
    $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'SurfaceWinPEDrivers.psd1'
    Import-Module $modulePath -Force
}

Describe 'Surface driver-pack selection for WinPE' {
    InModuleScope SurfaceWinPEDrivers {
        It 'accepts a legacy Win10-named Surface MSI when that is the current pack' {
            Mock Get-SurfaceDownloadCenterData {
                [pscustomobject]@{
                    DetailsUrl = 'https://www.microsoft.com/download/details.aspx?id=1'
                    Files = @(
                        [pscustomobject]@{
                            name = 'SurfaceLaptop2_Win10_19041_22.080.1424.0.msi'
                            url = 'https://download.microsoft.com/laptop2.msi'
                            size = '123456'
                            datePublished = '2022-08-01T12:00:00Z'
                        }
                    )
                }
            }

            $pack = Get-SurfaceLatestDriverPack -DownloadCenterId 1 -DefaultCpuVendor Intel -DefaultArchitecture x64

            $pack.DriverPackFileName | Should -Be 'SurfaceLaptop2_Win10_19041_22.080.1424.0.msi'
            $pack.OsName | Should -Be 'Windows 10'
            $pack.OsBuildNumber | Should -Be 19041
        }

        It 'prefers the most recently published pack rather than the highest OS build number' {
            Mock Get-SurfaceDownloadCenterData {
                [pscustomobject]@{
                    DetailsUrl = 'https://www.microsoft.com/download/details.aspx?id=2'
                    Files = @(
                        [pscustomobject]@{
                            name = 'Example_Win11_26100_25.100.1.0.msi'
                            url = 'https://download.microsoft.com/older.msi'
                            size = '100'
                            datePublished = '2026-01-01T00:00:00Z'
                        },
                        [pscustomobject]@{
                            name = 'Example_Win11_22631_26.100.1.0.msi'
                            url = 'https://download.microsoft.com/newer.msi'
                            size = '100'
                            datePublished = '2026-09-01T00:00:00Z'
                        }
                    )
                }
            }

            $pack = Get-SurfaceLatestDriverPack -DownloadCenterId 2 -DefaultCpuVendor Intel -DefaultArchitecture x64

            $pack.DriverPackVersion | Should -Be '26.100.1.0'
            $pack.OsBuildNumber | Should -Be 22631
        }
    }
}

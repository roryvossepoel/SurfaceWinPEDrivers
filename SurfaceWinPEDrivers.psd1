@{
    RootModule           = 'SurfaceWinPEDrivers.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = '17da949d-1ca5-46ae-9efb-e678bc49cad4'
    Author               = 'Rory Vossepoel'
    CompanyName          = ''
    Copyright            = '(c) 2026 Rory Vossepoel. All rights reserved.'
    Description          = 'Dynamically discovers and downloads the Microsoft Surface drivers required for Windows PE.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport    = @(
        'Get-SurfaceWinPEModel',
        'Save-SurfaceWinPEDriver'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Surface', 'WinPE', 'WindowsPE', 'Driver', 'OSD', 'Deployment', 'ARM64')
            LicenseUri   = 'https://github.com/roryvossepoel/SurfaceWinPEDrivers/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/roryvossepoel/SurfaceWinPEDrivers'
            ReleaseNotes = 'Initial public release.'
        }
    }
}

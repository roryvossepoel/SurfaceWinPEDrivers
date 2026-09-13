# SurfaceWinPEDrivers

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/SurfaceWinPEDrivers?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/SurfaceWinPEDrivers)

`SurfaceWinPEDrivers` is a PowerShell module that dynamically discovers and downloads the Microsoft Surface drivers required for Windows PE.

The module does **not** maintain a static Surface model or WinPE driver list. Instead, it combines Microsoft's current Surface WinPE deployment guidance with the official Surface driver and firmware download catalog, resolves the newest supported Surface driver pack for each selected model, and copies only the WinPE driver folders Microsoft currently documents.

## Why

Surface driver packs are cumulative MSI packages intended for full Windows deployment and servicing. Windows PE generally needs only a subset of those drivers. Microsoft maintains that subset per Surface model under **Import folders** in its Windows PE deployment documentation.

`SurfaceWinPEDrivers` automates that process:

1. Discover Surface models from Microsoft's WinPE deployment guidance.
2. Read the required **Import folders** for each model.
3. Prefer Microsoft's explicit `SurfaceUpdate` folder guidance when a legacy model section also documents older `SurfacePlatformInstaller` paths.
4. Detect required extra WinPE packages such as `SurfaceHidMini_WinPE_Intel` or `SurfaceHidMini_WinPE_ARM` when Microsoft publishes them as prerequisites.
5. Match each WinPE model to the official Surface driver download catalog.
6. Resolve the newest supported Surface driver pack MSI for the selected model.
7. Download and administratively extract the MSI.
8. Copy only the documented WinPE driver folders to the requested output directory.
9. Add required prerequisite packages to the same model output.

The Surface MSI itself is never installed on the target Windows installation. The OS label in the MSI filename is treated as metadata rather than as a WinPE compatibility gate. This allows older models that remain in Microsoft's current WinPE guidance to use their current Win10-named driver pack while newer models use Win11-named packs.

## Microsoft sources

The module uses these Microsoft-maintained sources at runtime:

- [How to enable a Surface Laptop keyboard, Surface Pro Keyboard, or Surface Pro Type Cover during Windows deployment](https://learn.microsoft.com/en-us/surface/enable-surface-keyboard-for-windows-pe-deployment)
- [Manage & deploy Surface driver & firmware updates](https://learn.microsoft.com/en-us/surface/manage-surface-driver-and-firmware-updates)

Because both sources can change independently, discovery reports unmatched and ambiguous models instead of silently guessing.

## Installation

### PowerShell Gallery

Install the published module directly from the PowerShell Gallery:

```powershell
Install-Module SurfaceWinPEDrivers
```

### From GitHub

Clone the repository and import the module manifest:

```powershell
Import-Module .\SurfaceWinPEDrivers.psd1 -Force
```

## Commands

### Discover supported Surface WinPE models

```powershell
Get-SurfaceWinPEModel
```

Typical output:

```text
Model                                      Architecture ImportFolderCount RequiredPackageCount Status
-----                                      ------------ ----------------- -------------------- ------
Surface Laptop 8 - Intel                   x64          ...               1                    Matched
Surface Pro 12 - Intel                     x64          ...               1                    Matched
Surface Pro 11 and Surface Pro 11 5G ...   ARM64        ...               1                    Matched
```

Inspect everything Microsoft publishes for a model:

```powershell
Get-SurfaceWinPEModel -Model '*Pro 12*' | Format-List *
```

`ImportFolderSource` shows whether the folder list came from the model's primary **Import folders** block or from Microsoft's explicit newer-`SurfaceUpdate` guidance for a legacy model.

### CLI selection

```powershell
Save-SurfaceWinPEDriver `
    -Model 'Surface Laptop 8 - Intel','Surface Pro 12 - Intel' `
    -Path 'C:\WinPE\Surface'
```

### Interactive selection with Out-GridView

`Out-GridView` remains a normal PowerShell selection layer; the module does not depend on it internally.

```powershell
Get-SurfaceWinPEModel |
    Where-Object Status -eq 'Matched' |
    Out-GridView -Title 'Select Surface models' -PassThru |
    Save-SurfaceWinPEDriver -Path 'C:\WinPE\Surface'
```

### Pipeline selection

```powershell
Get-SurfaceWinPEModel |
    Where-Object Architecture -eq 'ARM64' |
    Save-SurfaceWinPEDriver -Path 'C:\WinPE\Surface'
```

## Dry run / manifest validation

A full dry run can validate **all** models without downloading the Surface MSI files:

```powershell
New-SurfaceWinPEManifest `
    -All `
    -Path '.\SurfaceWinPE.Manifest.json' `
    -Validate
```

The dry run checks that every WinPE model:

- has a non-empty Microsoft **Import folders** list;
- maps uniquely to the official Surface driver catalog;
- resolves a supported Surface driver pack MSI;
- has a reachable MSI download URL;
- includes every required prerequisite package Microsoft specifies;
- has a reachable prerequisite download URL.

The manifest records the selected MSI filename, driver-pack version, OS label/build, architecture, WinPE folder source, Import folders, prerequisites, and URL validation results.

It also records Surface models present in the general driver catalog but not currently present in the WinPE guidance. This makes changes on either Microsoft source visible.

A dry run for an interactive subset is also possible:

```powershell
Get-SurfaceWinPEModel |
    Out-GridView -Title 'Select Surface models to validate' -PassThru |
    New-SurfaceWinPEManifest -Path '.\SurfaceWinPE.Manifest.json' -Validate
```

The dry run deliberately does **not** download and extract every MSI. Physical verification that Microsoft's documented Import folders exist in the selected MSI therefore happens in `Save-SurfaceWinPEDriver`.

## Required SurfaceHidMini WinPE packages

Some current Surface models require an additional package outside the regular Surface MSI. Microsoft currently documents folders such as:

- `SurfaceHidMini_WinPE_Intel`
- `SurfaceHidMini_WinPE_ARM`

These are discovered from the Microsoft WinPE page at runtime. When Microsoft marks one as required for a model, `SurfaceWinPEDrivers` treats it as a mandatory prerequisite:

- the manifest contains it under `WinPE.RequiredPackages`;
- `-Validate` fails if its download URL cannot be resolved or reached;
- `Save-SurfaceWinPEDriver` always downloads and adds the required folder to the model output;
- a missing required folder in the downloaded archive causes the build to fail rather than creating incomplete output.

There is no static model list for this prerequisite.

## Output

For example:

```text
C:\WinPE\Surface\
├── Surface Laptop 8 - Intel\
│   ├── acpiplatformextension\
│   ├── batteryclient\
│   ├── ...
│   ├── SurfaceHidMini_WinPE_Intel\
│   └── .surfacewinpe.json
│
└── Surface Pro 12 - Intel\
    ├── ...
    ├── SurfaceHidMini_WinPE_Intel\
    └── .surfacewinpe.json
```

Only the final WinPE driver folders are retained in the output directory. The MSI, expanded MSI contents, and downloaded prerequisite archives are temporary working data and are removed after a successful build. If a build fails, the temporary working directory is preserved and its path is shown for troubleshooting.

The `.surfacewinpe.json` file records the selected driver pack, OS label/build, Import folders, folder-source metadata, prerequisites, configuration hash, and any Microsoft guidance mismatch encountered while building the output.

A later run skips a model when both the selected driver pack version and Microsoft's current WinPE driver configuration are unchanged. Use `-Force` to rebuild it anyway. Existing output with a recorded guidance mismatch returns `CurrentWithWarnings` without downloading the MSI again.

## Guidance mismatch behavior

Microsoft Learn and the currently published Surface MSI are separate sources and can temporarily be out of sync.

When at least one documented Import folder is present but other documented folders are missing, the module:

- emits a warning;
- copies the documented folders that are actually present;
- records the missing folder names in `.surfacewinpe.json` under `MissingImportFolders`;
- records a `MicrosoftGuidanceMismatch` warning in the metadata;
- returns `SavedWithWarnings` (or `CurrentWithWarnings` on a later unchanged run).

Required prerequisite packages remain mandatory and are **not** downgraded to warnings.

## Safety and validation behavior

The module intentionally fails rather than silently guessing when:

- a WinPE model cannot be matched uniquely to a Microsoft driver download entry;
- Microsoft publishes no Import folders for the selected model;
- no supported Surface driver pack MSI can be resolved;
- none of the Microsoft-published WinPE Import folders can be found after extracting the selected Surface MSI;
- a required `SurfaceHidMini_WinPE_*` package has no resolvable download URL;
- a required prerequisite folder cannot be found inside its archive.

A partial Import-folder mismatch is handled as the explicit warning scenario described above instead of as a hard failure.

## Requirements

- Windows is required for `Save-SurfaceWinPEDriver` because Surface MSI files are expanded with `msiexec.exe`.
- Windows PowerShell 5.1 or PowerShell 7+ is supported by the module manifest.
- Internet access to Microsoft Learn, `microsoft.com`, and `download.microsoft.com` is required.
- `Out-GridView` is optional and only required when you choose to use interactive selection.

## CI

The repository contains:

- Pester unit tests for model normalization, source parsing, legacy/newer MSI folder guidance, driver-pack selection, and configuration hashing;
- Windows PowerShell 5.1 module import validation;
- a live Microsoft smoke test that builds and validates a manifest without downloading MSI contents;
- a weekly scheduled live smoke test to detect upstream Microsoft page/catalog changes.

## License

MIT

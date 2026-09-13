# Changelog

All notable changes to this project will be documented in this file.

## 1.0.0

Initial release.

- Dynamically discovers Surface models from Microsoft Windows PE deployment guidance.
- Dynamically reads Microsoft-published WinPE `Import folders` per model.
- Prefers Microsoft's explicit newer-`SurfaceUpdate` folder guidance when legacy sections also document older MSI layouts.
- Dynamically matches WinPE models to the official Surface driver and firmware catalog.
- Resolves the newest supported Surface driver pack MSI per model, including Win10-named packs for older models that remain in Microsoft's current WinPE guidance.
- Supports CLI selection and PowerShell pipeline selection, including `Out-GridView -PassThru`.
- Supports a configurable output directory and idempotent rebuild detection.
- Automatically detects and includes required `SurfaceHidMini_WinPE_Intel` and `SurfaceHidMini_WinPE_ARM` packages when Microsoft documents them as prerequisites.
- Provides full manifest/dry-run URL and metadata validation without downloading Surface MSI contents.
- Warns and records metadata when Microsoft Learn lists some Import folders that are absent from the currently published MSI, while continuing with documented folders that are present.
- Fails when no documented Import folders can be found or when a required prerequisite cannot be resolved or added.
- Preserves the temporary extraction directory when a build fails to simplify troubleshooting.
- Includes Pester tests and a live Microsoft smoke test.

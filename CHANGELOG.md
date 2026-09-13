# Changelog

All notable changes to this project will be documented in this file.

## 1.0.0

Initial release.

- Dynamically discovers Surface models from Microsoft Windows PE deployment guidance.
- Dynamically reads Microsoft-published WinPE `Import folders` per model.
- Dynamically matches WinPE models to the official Surface driver and firmware catalog.
- Resolves the newest available Windows 11 Surface MSI per model.
- Supports CLI selection and PowerShell pipeline selection, including `Out-GridView -PassThru`.
- Supports a configurable output directory.
- Automatically detects and includes required `SurfaceHidMini_WinPE_Intel` and `SurfaceHidMini_WinPE_ARM` packages when Microsoft documents them as prerequisites.
- Provides full manifest/dry-run validation without downloading Surface MSI contents.
- Fails on incomplete WinPE driver sets instead of silently producing partial output.
- Includes Pester tests and a live Microsoft smoke test.

# UpdateRemarkable

A PowerShell automation tool for installing custom templates on a reMarkable Paper Pro tablet.  This project contains the PowerShell script and a set of unit tests to support updates.  I developed this script/repo using AI workflows. 

## Background

After every system update, the reMarkable Paper Pro resets its custom templates. Re-adding them used to be a tedious manual process involving two command windows, multiple SSH/SCP commands, and careful JSON editing (the original manual steps are preserved in `Template_Update_Instructions.md`).

This project automates that entire workflow into a single PowerShell script. The script was built iteratively with the help of GitHub Copilot — starting from the manual instructions, then extracting testable functions into a module, and adding a full Pester 5 test suite to validate correctness before connecting to a real device. 

## Running the Script

Connect the reMarkable Paper Pro to your computer via USB, then run:

```powershell
.\Update-RemarkableTemplates.ps1
```

The script will prompt for any missing parameters interactively.

### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-DeviceIP` | String | No | IP address of the reMarkable device. If omitted, prompts with a default of `10.11.99.1`. |
| `-WorkingDirectory` | String | No | Directory where the timestamped backup folder will be created. If omitted, opens a folder-browser dialog. |

### Examples

```powershell
# Interactive — prompts for all values
.\Update-RemarkableTemplates.ps1

# Specify IP only
.\Update-RemarkableTemplates.ps1 -DeviceIP "10.11.99.1"

# Fully non-interactive (except password prompt)
.\Update-RemarkableTemplates.ps1 -DeviceIP "10.11.99.1" -WorkingDirectory "C:\Backups"
```

### What the Script Does

1. **Validates** that `templates_to_add.json` and the `CustomTemplates/` folder are in sync
2. **Backs up** the device's current `templates.json`
3. **Merges** custom templates into the device list, skipping any already present
4. **Deploys** the updated `templates.json` and new `.template` files to the device (remounts filesystem as read-write, then back to read-only)
5. **Prompts** you to reboot the device to apply changes

> **Note:** Each SSH and SCP command will prompt for the device password interactively.

## Running the Tests

The test suite uses [Pester 5](https://pester.dev/) and requires no device connection.

```powershell
# Install Pester 5 (one-time)
Install-Module -Name Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck -Scope CurrentUser

# Run all tests
Import-Module Pester -MinimumVersion 5.0 -Force
Invoke-Pester -Path .\Update-RemarkableTemplates.Tests.ps1 -Output Detailed
```

To run a single test by name:

```powershell
Invoke-Pester -Path .\Update-RemarkableTemplates.Tests.ps1 -Output Detailed -Filter @{ FullName = "*partial overlap*" }
```

## Repository Files

| File | Description |
|---|---|
| `Update-RemarkableTemplates.ps1` | Main script — automates the full template installation workflow. |
| `RemarkableTemplates.psm1` | PowerShell module containing the extracted, testable functions (validation, merge, SSH/SCP helpers). |
| `Update-RemarkableTemplates.Tests.ps1` | Pester 5 test suite — 20 tests covering validation, merge logic, mocked SSH/SCP, and end-to-end scenarios. |
| `templates_to_add.json` | JSON manifest of custom templates to install. Each entry has a `name`, `filename`, `iconCode`, and `categories`. |
| `CustomTemplates/` | Directory containing the `.template` image files referenced by `templates_to_add.json`. |
| `Template_Update_Instructions.md` | Original manual instructions for updating templates — retained as a reference. |

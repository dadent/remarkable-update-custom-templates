<#
.SYNOPSIS
    Re-installs custom templates on a reMarkable Paper Pro after a system update.

.DESCRIPTION
    Automates the process of adding custom templates to a reMarkable Paper Pro device.
    Uses native Windows OpenSSH for all device communication. Each SSH and SCP command will prompt for the device password interactively.

.PARAMETER DeviceIP
    IP address of the reMarkable device. Defaults to prompting with 10.11.99.1.

.PARAMETER WorkingDirectory
    Directory where the timestamped backup folder will be created.
    If omitted, opens a folder-browser dialog.

.EXAMPLE
    .\Update-RemarkableTemplates.ps1
    .\Update-RemarkableTemplates.ps1 -DeviceIP "10.11.99.1"
    .\Update-RemarkableTemplates.ps1 -DeviceIP "10.11.99.1" -WorkingDirectory "C:\Backups"
#>

param(
    [string]$DeviceIP,
    [string]$WorkingDirectory
)

$ErrorActionPreference = "Stop"

# --- Import module ---
Import-Module (Join-Path $PSScriptRoot "RemarkableTemplates.psm1") -Force

# --- Constants ---
$RemoteTemplateDir = "/usr/share/remarkable/templates"
$RemoteUser = "root"
$TemplatesToAddPath = Join-Path $PSScriptRoot "templates_to_add.json"
$CustomTemplatesDir = Join-Path $PSScriptRoot "CustomTemplates"

# =====================================================================
# PHASE 1: Setup & Validation
# =====================================================================

Write-Host "`n=== reMarkable Custom Template Installer ===" -ForegroundColor Cyan
Write-Host ""

# --- Prompt for parameters if not provided ---

# Device IP
if (-not $DeviceIP) {
    $inputIP = Read-Host "Enter device IP address [10.11.99.1]"
    $DeviceIP = if ($inputIP) { $inputIP } else { "10.11.99.1" }
}
Write-Host "Device IP: $DeviceIP" -ForegroundColor Green

# Working Directory
if (-not $WorkingDirectory) {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select the directory for the backup/working folder"
    $dialog.ShowNewFolderButton = $true
    $result = $dialog.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host "No directory selected. Exiting." -ForegroundColor Yellow
        exit 1
    }
    $WorkingDirectory = $dialog.SelectedPath
}
if (-not (Test-Path $WorkingDirectory)) {
    throw "Working directory does not exist: $WorkingDirectory"
}
Write-Host "Working directory: $WorkingDirectory" -ForegroundColor Green

# --- Validate templates_to_add.json and CustomTemplates/ ---

Write-Host "`nValidating template files..." -ForegroundColor Cyan

$templatesToAdd = Test-TemplateFiles -TemplatesToAddPath $TemplatesToAddPath -CustomTemplatesDir $CustomTemplatesDir

Write-Host "  Validated $($templatesToAdd.Count) template(s) - all files and JSON entries match." -ForegroundColor Green

# Track state for cleanup
$fsReadWrite = $false
try {
    # =================================================================
    # PHASE 3: Connect & Backup
    # =================================================================

    Write-Host "`nCreating backup..." -ForegroundColor Cyan

    $timestamp = Get-Date -Format "yyyy_MM_dd_HHmmss"
    $workingFolder = Join-Path $WorkingDirectory "Update_$timestamp"
    New-Item -ItemType Directory -Path $workingFolder -Force | Out-Null
    Write-Host "  Working folder: $workingFolder" -ForegroundColor Green

    $sourceTemplatesPath = Join-Path $workingFolder "source_templates.json"
    Receive-FileFromDevice -IP $DeviceIP -RemotePath "$RemoteTemplateDir/templates.json" -LocalPath $sourceTemplatesPath
    Write-Host "  Device templates.json backed up to: $sourceTemplatesPath" -ForegroundColor Green

    # =================================================================
    # PHASE 4: Merge Templates
    # =================================================================

    Write-Host "`nMerging templates..." -ForegroundColor Cyan

    $deviceTemplates = Get-Content $sourceTemplatesPath -Raw | ConvertFrom-Json
    $mergeResult = Merge-Templates -DeviceTemplates $deviceTemplates.templates -CustomTemplates $templatesToAdd

    $toAdd = $mergeResult.Added
    $skipped = $mergeResult.Skipped

    if ($skipped.Count -gt 0) {
        Write-Host "  Skipping (already on device):" -ForegroundColor Yellow
        foreach ($s in $skipped) {
            Write-Host "    - $($s.name) ($($s.filename))" -ForegroundColor Yellow
        }
    }

    if ($toAdd.Count -eq 0) {
        Write-Host "`nAll custom templates are already installed on the device. Nothing to do." -ForegroundColor Green
    } else {
        Write-Host "  Adding:" -ForegroundColor Green
        foreach ($a in $toAdd) {
            Write-Host "    + $($a.name) ($($a.filename))" -ForegroundColor Green
        }

        # Build merged JSON
        $mergedObject = @{ templates = $mergeResult.Merged }
        $updatedTemplatesPath = Join-Path $workingFolder "updated_templates.json"
        $mergedObject | ConvertTo-Json -Depth 10 | Set-Content -Path $updatedTemplatesPath -Encoding UTF8
        Write-Host "  Merged templates saved to: $updatedTemplatesPath" -ForegroundColor Green

        # =============================================================
        # PHASE 5: Deploy to Device
        # =============================================================

        Write-Host "`nDeploying to device..." -ForegroundColor Cyan

        # Remount as read-write
        Write-Host "  Remounting filesystem as read-write..." -ForegroundColor White
        Invoke-RemoteSSH -IP $DeviceIP -Command "mount -o remount,rw /"
        $fsReadWrite = $true

        # Upload new .template files
        foreach ($a in $toAdd) {
            $templateFilePath = Join-Path $CustomTemplatesDir "$($a.filename).template"
            Write-Host "  Uploading: $($a.filename).template" -ForegroundColor White
            Send-FileToDevice -IP $DeviceIP -LocalPath $templateFilePath -RemotePath "$RemoteTemplateDir/"
        }

        # Upload merged templates.json
        Write-Host "  Uploading updated templates.json..." -ForegroundColor White
        Send-FileToDevice -IP $DeviceIP -LocalPath $updatedTemplatesPath -RemotePath "$RemoteTemplateDir/templates.json"

        # Remount as read-only
        Write-Host "  Remounting filesystem as read-only..." -ForegroundColor White
        Invoke-RemoteSSH -IP $DeviceIP -Command "mount -o remount,ro /"
        $fsReadWrite = $false

        Write-Host "  Deployment complete." -ForegroundColor Green
    }
}
finally {
    # =================================================================
    # PHASE 6: Cleanup
    # =================================================================

    Write-Host "`nCleaning up..." -ForegroundColor Cyan

    # Remount read-only if still read-write (error recovery)
    if ($fsReadWrite) {
        Write-Host "  Remounting filesystem as read-only (error recovery)..." -ForegroundColor Yellow
        try {
            Invoke-RemoteSSH -IP $DeviceIP -Command "mount -o remount,ro /"
        } catch {
            Write-Host "  WARNING: Failed to remount filesystem as read-only: $_" -ForegroundColor Red
        }
    }
}

# =====================================================================
# Summary & Reboot Prompt
# =====================================================================

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "  Backup location: $workingFolder" -ForegroundColor White
if ($toAdd.Count -gt 0) {
    Write-Host "  Templates added: $($toAdd.Count)" -ForegroundColor Green
    foreach ($a in $toAdd) {
        Write-Host "    + $($a.name)" -ForegroundColor Green
    }
}
if ($skipped.Count -gt 0) {
    Write-Host "  Templates skipped (already present): $($skipped.Count)" -ForegroundColor Yellow
    foreach ($s in $skipped) {
        Write-Host "    - $($s.name)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== ACTION REQUIRED ===" -ForegroundColor Yellow
Write-Host "  1. Unplug the USB cable from the reMarkable device." -ForegroundColor Yellow
Write-Host "  2. On the device, go to Settings and select Restart." -ForegroundColor Yellow
Write-Host ""
Read-Host "Press Enter after you have rebooted the device"
Write-Host "`nDone!" -ForegroundColor Green

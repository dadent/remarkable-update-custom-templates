<#
.SYNOPSIS
    Reusable functions for managing reMarkable Paper Pro custom templates.

.DESCRIPTION
    Contains validation, merge, and SSH/SCP helper functions extracted from
    Update-RemarkableTemplates.ps1 for testability.
#>

$ErrorActionPreference = "Stop"

# --- Module-scoped defaults ---
$script:RemoteUser = "root"
$script:RemoteTemplateDir = "/usr/share/remarkable/templates"

# --- SSH/SCP Helpers ---

function Invoke-RemoteSSH {
    param(
        [Parameter(Mandatory)][string]$IP,
        [Parameter(Mandatory)][string]$KeyPath,
        [Parameter(Mandatory)][string]$Command
    )
    $output = & ssh -i $KeyPath -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o BatchMode=yes "${script:RemoteUser}@${IP}" $Command 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "SSH command failed (exit code $LASTEXITCODE): $Command`n$output"
    }
    return $output
}

function Send-FileToDevice {
    param(
        [Parameter(Mandatory)][string]$IP,
        [Parameter(Mandatory)][string]$KeyPath,
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string]$RemotePath
    )
    & scp -i $KeyPath -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o BatchMode=yes $LocalPath "${script:RemoteUser}@${IP}:${RemotePath}" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "SCP upload failed for: $LocalPath"
    }
}

function Receive-FileFromDevice {
    param(
        [Parameter(Mandatory)][string]$IP,
        [Parameter(Mandatory)][string]$KeyPath,
        [Parameter(Mandatory)][string]$RemotePath,
        [Parameter(Mandatory)][string]$LocalPath
    )
    & scp -i $KeyPath -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o BatchMode=yes "${script:RemoteUser}@${IP}:${RemotePath}" $LocalPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "SCP download failed for: $RemotePath"
    }
}

# --- Validation ---

function Test-TemplateFiles {
    <#
    .SYNOPSIS
        Validates that templates_to_add.json entries match CustomTemplates/*.template files.
    .OUTPUTS
        Returns the parsed templates array from templates_to_add.json on success.
    #>
    param(
        [Parameter(Mandatory)][string]$TemplatesToAddPath,
        [Parameter(Mandatory)][string]$CustomTemplatesDir
    )

    if (-not (Test-Path $TemplatesToAddPath)) {
        throw "templates_to_add.json not found at: $TemplatesToAddPath"
    }
    if (-not (Test-Path $CustomTemplatesDir)) {
        throw "CustomTemplates directory not found at: $CustomTemplatesDir"
    }

    $templatesToAdd = (Get-Content $TemplatesToAddPath -Raw | ConvertFrom-Json).templates
    $templateFiles = Get-ChildItem -Path $CustomTemplatesDir -Filter "*.template" | ForEach-Object { $_.BaseName }

    # Handle empty case: both null/empty is valid
    $jsonFilenames = @()
    if ($templatesToAdd) {
        $jsonFilenames = @($templatesToAdd | ForEach-Object { $_.filename })
    }
    $templateFileNames = @()
    if ($templateFiles) {
        $templateFileNames = @($templateFiles)
    }

    # Check every JSON entry has a matching .template file
    $missingFiles = $jsonFilenames | Where-Object { $_ -notin $templateFileNames }
    if ($missingFiles) {
        throw "The following entries in templates_to_add.json have no matching .template file in CustomTemplates/:`n  $($missingFiles -join "`n  ")"
    }

    # Check every .template file has a matching JSON entry
    $missingEntries = $templateFileNames | Where-Object { $_ -notin $jsonFilenames }
    if ($missingEntries) {
        throw "The following .template files in CustomTemplates/ have no matching entry in templates_to_add.json:`n  $($missingEntries -join "`n  ")"
    }

    return $templatesToAdd
}

# --- Merge ---

function Merge-Templates {
    <#
    .SYNOPSIS
        Merges custom templates into the device template list, skipping duplicates.
    .OUTPUTS
        PSCustomObject with properties: Merged (array), Added (array), Skipped (array)
    #>
    param(
        [Parameter()][array]$DeviceTemplates = @(),
        [Parameter()][array]$CustomTemplates = @()
    )

    $deviceFilenames = @($DeviceTemplates | ForEach-Object { $_.filename })

    $toAdd = @()
    $skipped = @()

    foreach ($template in $CustomTemplates) {
        if ($template.filename -in $deviceFilenames) {
            $skipped += $template
        } else {
            $toAdd += $template
        }
    }

    $merged = @($DeviceTemplates)
    foreach ($a in $toAdd) {
        $merged += $a
    }

    return [PSCustomObject]@{
        Merged  = $merged
        Added   = $toAdd
        Skipped = $skipped
    }
}

Export-ModuleMember -Function Invoke-RemoteSSH, Send-FileToDevice, Receive-FileFromDevice, Test-TemplateFiles, Merge-Templates

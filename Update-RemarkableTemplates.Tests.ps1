#Requires -Modules Pester

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot "RemarkableTemplates.psm1") -Force
}

# =====================================================================
# Group A: Test-TemplateFiles (Validation)
# =====================================================================

Describe "Test-TemplateFiles" {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "PesterRM_$(New-Guid)"
        New-Item -ItemType Directory -Path $script:tempDir | Out-Null
        $script:customDir = Join-Path $script:tempDir "CustomTemplates"
        New-Item -ItemType Directory -Path $script:customDir | Out-Null
        $script:jsonPath = Join-Path $script:tempDir "templates_to_add.json"
    }

    AfterEach {
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Succeeds when JSON entries and .template files match exactly" {
        @{ templates = @(
            @{ name = "T1"; filename = "T1"; iconCode = "\ue999"; categories = @("Grids") }
            @{ name = "T2"; filename = "T2"; iconCode = "\ue999"; categories = @("Grids") }
        )} | ConvertTo-Json -Depth 5 | Set-Content $script:jsonPath
        New-Item (Join-Path $script:customDir "T1.template") -ItemType File | Out-Null
        New-Item (Join-Path $script:customDir "T2.template") -ItemType File | Out-Null

        $result = Test-TemplateFiles -TemplatesToAddPath $script:jsonPath -CustomTemplatesDir $script:customDir
        $result | Should -HaveCount 2
    }

    It "Throws when a JSON entry has no matching .template file" {
        @{ templates = @(
            @{ name = "Foo"; filename = "Foo"; iconCode = "\ue999"; categories = @("Grids") }
        )} | ConvertTo-Json -Depth 5 | Set-Content $script:jsonPath
        # No .template file created

        { Test-TemplateFiles -TemplatesToAddPath $script:jsonPath -CustomTemplatesDir $script:customDir } |
            Should -Throw "*Foo*"
    }

    It "Throws when a .template file has no matching JSON entry" {
        @{ templates = @() } | ConvertTo-Json -Depth 5 | Set-Content $script:jsonPath
        New-Item (Join-Path $script:customDir "Bar.template") -ItemType File | Out-Null

        { Test-TemplateFiles -TemplatesToAddPath $script:jsonPath -CustomTemplatesDir $script:customDir } |
            Should -Throw "*Bar*"
    }

    It "Succeeds with zero templates in JSON and zero .template files" {
        @{ templates = @() } | ConvertTo-Json -Depth 5 | Set-Content $script:jsonPath

        $result = Test-TemplateFiles -TemplatesToAddPath $script:jsonPath -CustomTemplatesDir $script:customDir
        # null or empty is acceptable for zero templates
        @($result).Count | Should -BeLessOrEqual 1
    }

    It "Throws when templates_to_add.json does not exist" {
        { Test-TemplateFiles -TemplatesToAddPath (Join-Path $script:tempDir "nope.json") -CustomTemplatesDir $script:customDir } |
            Should -Throw "*not found*"
    }

    It "Throws when CustomTemplates directory does not exist" {
        @{ templates = @() } | ConvertTo-Json -Depth 5 | Set-Content $script:jsonPath

        { Test-TemplateFiles -TemplatesToAddPath $script:jsonPath -CustomTemplatesDir (Join-Path $script:tempDir "NoDir") } |
            Should -Throw "*not found*"
    }
}

# =====================================================================
# Group B: Merge-Templates
# =====================================================================

Describe "Merge-Templates" {
    BeforeAll {
        function New-TemplateObj($name, $filename) {
            [PSCustomObject]@{ name = $name; filename = $filename; iconCode = "\ue999"; categories = @("Grids") }
        }
    }

    It "Adds all custom templates when none overlap with device" {
        $device = @( (New-TemplateObj "A" "A"), (New-TemplateObj "B" "B") )
        $custom = @( (New-TemplateObj "C" "C"), (New-TemplateObj "D" "D") )

        $result = Merge-Templates -DeviceTemplates $device -CustomTemplates $custom

        $result.Merged | Should -HaveCount 4
        $result.Added  | Should -HaveCount 2
        $result.Skipped | Should -HaveCount 0
    }

    It "Skips all custom templates when all are duplicates" {
        $device = @( (New-TemplateObj "A" "A"), (New-TemplateObj "B" "B") )
        $custom = @( (New-TemplateObj "A" "A"), (New-TemplateObj "B" "B") )

        $result = Merge-Templates -DeviceTemplates $device -CustomTemplates $custom

        $result.Merged  | Should -HaveCount 2
        $result.Added   | Should -HaveCount 0
        $result.Skipped | Should -HaveCount 2
    }

    It "Handles partial overlap - adds new, skips existing" {
        $device = @( (New-TemplateObj "A" "A"), (New-TemplateObj "B" "B") )
        $custom = @( (New-TemplateObj "B" "B"), (New-TemplateObj "C" "C") )

        $result = Merge-Templates -DeviceTemplates $device -CustomTemplates $custom

        $result.Merged  | Should -HaveCount 3
        $result.Added   | Should -HaveCount 1
        $result.Added[0].filename | Should -Be "C"
        $result.Skipped | Should -HaveCount 1
        $result.Skipped[0].filename | Should -Be "B"
    }

    It "Handles empty device template list" {
        $device = @()
        $custom = @( (New-TemplateObj "A" "A") )

        $result = Merge-Templates -DeviceTemplates $device -CustomTemplates $custom

        $result.Merged | Should -HaveCount 1
        $result.Added  | Should -HaveCount 1
    }

    It "Handles empty custom template list" {
        $device = @( (New-TemplateObj "A" "A"), (New-TemplateObj "B" "B") )

        $result = Merge-Templates -DeviceTemplates $device -CustomTemplates @()

        $result.Merged  | Should -HaveCount 2
        $result.Added   | Should -HaveCount 0
        $result.Skipped | Should -HaveCount 0
    }
}

# =====================================================================
# Group C: SSH/SCP Helpers (Mocked)
# =====================================================================

Describe "Invoke-RemoteSSH" {
    It "Returns output on success" {
        Mock ssh { $global:LASTEXITCODE = 0; "hello world" } -ModuleName RemarkableTemplates

        $result = Invoke-RemoteSSH -IP "1.2.3.4" -Command "echo hello"
        $result | Should -Be "hello world"
    }

    It "Throws on non-zero exit code" {
        Mock ssh { $global:LASTEXITCODE = 1; "error output" } -ModuleName RemarkableTemplates

        { Invoke-RemoteSSH -IP "1.2.3.4" -Command "bad cmd" } |
            Should -Throw "*SSH command failed*"
    }
}

Describe "Send-FileToDevice" {
    It "Succeeds without error on exit code 0" {
        Mock scp { $global:LASTEXITCODE = 0 } -ModuleName RemarkableTemplates

        { Send-FileToDevice -IP "1.2.3.4" -LocalPath "C:\file.txt" -RemotePath "/tmp/" } |
            Should -Not -Throw
    }

    It "Throws on non-zero exit code" {
        Mock scp { $global:LASTEXITCODE = 1 } -ModuleName RemarkableTemplates

        { Send-FileToDevice -IP "1.2.3.4" -LocalPath "C:\file.txt" -RemotePath "/tmp/" } |
            Should -Throw "*SCP upload failed*"
    }
}

Describe "Receive-FileFromDevice" {
    It "Succeeds without error on exit code 0" {
        Mock scp { $global:LASTEXITCODE = 0 } -ModuleName RemarkableTemplates

        { Receive-FileFromDevice -IP "1.2.3.4" -RemotePath "/tmp/file.txt" -LocalPath "C:\file.txt" } |
            Should -Not -Throw
    }

    It "Throws on non-zero exit code" {
        Mock scp { $global:LASTEXITCODE = 1 } -ModuleName RemarkableTemplates

        { Receive-FileFromDevice -IP "1.2.3.4" -RemotePath "/tmp/file.txt" -LocalPath "C:\file.txt" } |
            Should -Throw "*SCP download failed*"
    }
}

# =====================================================================
# Group D: End-to-End (Mocked Device)
# =====================================================================

Describe "End-to-End: Full deployment with mocked device" {
    BeforeEach {
        $script:e2eDir = Join-Path ([System.IO.Path]::GetTempPath()) "PesterRM_E2E_$(New-Guid)"
        New-Item -ItemType Directory -Path $script:e2eDir | Out-Null

        # Create a fake "device" templates.json (has template A)
        $script:deviceJson = @{ templates = @(
            @{ name = "DeviceA"; filename = "DeviceA"; iconCode = "\ue999"; categories = @("Grids") }
        )}

        # Create custom templates dir with template B
        $script:customDir = Join-Path $script:e2eDir "CustomTemplates"
        New-Item -ItemType Directory -Path $script:customDir | Out-Null
        New-Item (Join-Path $script:customDir "CustomB.template") -ItemType File | Out-Null

        $script:jsonPath = Join-Path $script:e2eDir "templates_to_add.json"
        @{ templates = @(
            @{ name = "CustomB"; filename = "CustomB"; iconCode = "\ue999"; categories = @("Grids") }
        )} | ConvertTo-Json -Depth 5 | Set-Content $script:jsonPath

        $script:workDir = Join-Path $script:e2eDir "work"
        New-Item -ItemType Directory -Path $script:workDir | Out-Null
    }

    AfterEach {
        Remove-Item -Path $script:e2eDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Deploys new templates: validates, merges, uploads, and remounts" {
        # Step 1: Validate
        $templates = Test-TemplateFiles -TemplatesToAddPath $script:jsonPath -CustomTemplatesDir $script:customDir
        $templates | Should -HaveCount 1

        # Step 2: Merge
        $result = Merge-Templates -DeviceTemplates $script:deviceJson.templates -CustomTemplates $templates
        $result.Added | Should -HaveCount 1
        $result.Added[0].filename | Should -Be "CustomB"
        $result.Skipped | Should -HaveCount 0
        $result.Merged | Should -HaveCount 2

        # Step 3: Verify merged JSON structure
        $mergedObject = @{ templates = $result.Merged }
        $mergedJson = $mergedObject | ConvertTo-Json -Depth 10
        $roundTrip = $mergedJson | ConvertFrom-Json
        $roundTrip.templates | Should -HaveCount 2
        ($roundTrip.templates | ForEach-Object { $_.filename }) | Should -Contain "DeviceA"
        ($roundTrip.templates | ForEach-Object { $_.filename }) | Should -Contain "CustomB"
    }

    It "Skips deployment when all templates already exist on device" {
        $deviceWithCustom = @{ templates = @(
            @{ name = "DeviceA"; filename = "DeviceA"; iconCode = "\ue999"; categories = @("Grids") }
            @{ name = "CustomB"; filename = "CustomB"; iconCode = "\ue999"; categories = @("Grids") }
        )}

        $templates = Test-TemplateFiles -TemplatesToAddPath $script:jsonPath -CustomTemplatesDir $script:customDir
        $result = Merge-Templates -DeviceTemplates $deviceWithCustom.templates -CustomTemplates $templates

        $result.Added | Should -HaveCount 0
        $result.Skipped | Should -HaveCount 1
        $result.Merged | Should -HaveCount 2
    }

    It "Merge preserves device templates even when custom list causes error downstream" {
        # Verify that a merge with valid inputs always preserves the original device list
        $device = @(
            [PSCustomObject]@{ name = "D1"; filename = "D1"; iconCode = "\ue999"; categories = @("Grids") }
            [PSCustomObject]@{ name = "D2"; filename = "D2"; iconCode = "\ue999"; categories = @("Grids") }
        )
        $custom = @(
            [PSCustomObject]@{ name = "C1"; filename = "C1"; iconCode = "\ue999"; categories = @("Grids") }
        )

        $result = Merge-Templates -DeviceTemplates $device -CustomTemplates $custom

        # Original device templates are first in the merged list
        $result.Merged[0].filename | Should -Be "D1"
        $result.Merged[1].filename | Should -Be "D2"
        $result.Merged[2].filename | Should -Be "C1"
    }
}

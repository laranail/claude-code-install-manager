<#
.SYNOPSIS
    Pester 5 tests for scripts/build-launcher.ps1.

.DESCRIPTION
    The build script's actual compilation step needs csc.exe, which only
    exists on Windows. Tests in this file are written so they run on any
    platform where Pester runs (the parameter-validation, path-resolution,
    helper-discovery checks) — the actual-compile case is tagged with
    -Tag 'Integration' and 'Windows' so CI can decide whether to run them.

.NOTES
    Run from repository root:

        Invoke-Pester -Path ./scripts/tests -Output Detailed

    Or just the unit-level cases (no compile required):

        Invoke-Pester -Path ./scripts/tests -ExcludeTag Integration
#>
#Requires -Version 5.1

BeforeAll {
    $script:repoRoot   = (Resolve-Path "$PSScriptRoot/../..").Path
    $script:scriptsDir = Join-Path $repoRoot 'scripts'
    $script:buildPs1   = Join-Path $scriptsDir 'build-launcher.ps1'
    $script:launcherCs = Join-Path $scriptsDir 'launcher.cs'
}

Describe 'build-launcher.ps1 — file presence' {
    It 'exists at the expected path' {
        Test-Path -LiteralPath $script:buildPs1 | Should -Be $true
    }

    It 'parses as valid PowerShell' {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $script:buildPs1, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0 -Because "the build script must parse cleanly"
    }
}

Describe 'launcher.cs — source presence' {
    It 'exists at the expected path' {
        Test-Path -LiteralPath $script:launcherCs | Should -Be $true
    }

    It 'declares the expected namespace' {
        $content = Get-Content -LiteralPath $script:launcherCs -Raw
        $content | Should -Match 'namespace Simtabi\.ClaudeCodeInstallManager'
    }

    It 'references the expected .cmd filename' {
        $content = Get-Content -LiteralPath $script:launcherCs -Raw
        $content | Should -Match 'claude-code-install-manager\.cmd'
    }
}

Describe 'build-launcher.ps1 — parameter sets' {
    BeforeAll {
        # Pull parameter metadata WITHOUT executing the script body.
        $script:cmdInfo = Get-Command -Syntax $script:buildPs1
    }

    It 'declares a CertPath parameter' {
        $script:cmdInfo | Should -Match '-CertPath'
    }

    It 'declares a Thumbprint parameter' {
        $script:cmdInfo | Should -Match '-Thumbprint'
    }

    It 'declares a SkipSign switch' {
        $script:cmdInfo | Should -Match '-SkipSign'
    }
}

Describe 'build-launcher.ps1 — dry-run with -SkipSign' -Tag 'Integration', 'Windows' {
    BeforeAll {
        $script:isWindows = $IsWindows -or [Environment]::OSVersion.Platform -eq 'Win32NT'
        $script:tempOut   = Join-Path ([IO.Path]::GetTempPath()) ("cct-build-" + [Guid]::NewGuid())
    }

    It 'produces claude-code-install-manager.exe and SHA256SUMS' -Skip:(-not $script:isWindows) {
        & $script:buildPs1 -OutDir $script:tempOut -SkipSign | Out-Null
        $LASTEXITCODE | Should -BeIn 0, $null

        (Join-Path $script:tempOut 'claude-code-install-manager.exe') |
            Should -Exist

        (Join-Path $script:tempOut 'claude-code-install-manager.cmd') |
            Should -Exist

        (Join-Path $script:tempOut 'SHA256SUMS') | Should -Exist
    }

    AfterAll {
        if (Test-Path -LiteralPath $script:tempOut) {
            Remove-Item -LiteralPath $script:tempOut -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

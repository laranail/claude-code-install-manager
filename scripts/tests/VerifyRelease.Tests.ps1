<#
.SYNOPSIS
    Pester 5 tests for scripts/verify-release.ps1.

.DESCRIPTION
    Builds a synthetic release directory (a couple of dummy files plus a
    SHA256SUMS that matches them), then drives verify-release.ps1 against
    it. Also runs it against a corrupted version to confirm the failure
    path returns a non-zero exit.

    These tests do NOT need Windows-specific tooling — they only exercise
    the hash / SHA256SUMS-parsing path. The Authenticode-check path is
    only exercised against a real signed PE, which we do not produce in
    unit tests.
#>
#Requires -Version 5.1

BeforeAll {
    $script:repoRoot   = (Resolve-Path "$PSScriptRoot/../..").Path
    $script:verifyPs1  = Join-Path $repoRoot 'scripts/verify-release.ps1'

    function New-FakeRelease {
        param(
            [string] $Dir,
            [string] $CorruptName
        )
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
        $files = @(
            @{ Name = 'claude-code-install-manager.cmd'; Body = "REM dummy cmd`r`nexit /b 0" }
            @{ Name = 'README.md';                       Body = "# fake`n" }
        )
        $lines = foreach ($f in $files) {
            $p = Join-Path $Dir $f.Name
            Set-Content -LiteralPath $p -Value $f.Body -NoNewline -Encoding ascii
        }
        # Compute hashes AFTER writing all files
        $lines = foreach ($f in $files) {
            $p = Join-Path $Dir $f.Name
            $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower()
            "$h  $($f.Name)"
        }
        Set-Content -LiteralPath (Join-Path $Dir 'SHA256SUMS') -Value $lines -Encoding ascii

        # Optionally corrupt one file AFTER its hash was recorded.
        if ($CorruptName) {
            Add-Content -LiteralPath (Join-Path $Dir $CorruptName) -Value 'TAMPER' -Encoding ascii
        }
    }
}

Describe 'verify-release.ps1 — file presence' {
    It 'exists at the expected path' {
        Test-Path -LiteralPath $script:verifyPs1 | Should -Be $true
    }

    It 'parses as valid PowerShell' {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $script:verifyPs1, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0
    }
}

Describe 'verify-release.ps1 — happy path' {
    BeforeAll {
        $script:tempDir = Join-Path ([IO.Path]::GetTempPath()) ("cct-verify-ok-" + [Guid]::NewGuid())
        New-FakeRelease -Dir $script:tempDir
    }

    It 'exits 0 against an unmodified release' {
        & $script:verifyPs1 -ReleaseDir $script:tempDir *> $null
        $LASTEXITCODE | Should -Be 0
    }

    AfterAll {
        Remove-Item -LiteralPath $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'verify-release.ps1 — corruption detection' {
    BeforeAll {
        $script:tempDir = Join-Path ([IO.Path]::GetTempPath()) ("cct-verify-bad-" + [Guid]::NewGuid())
        New-FakeRelease -Dir $script:tempDir -CorruptName 'README.md'
    }

    It 'exits non-zero when a file does not match SHA256SUMS' {
        & $script:verifyPs1 -ReleaseDir $script:tempDir *> $null
        $LASTEXITCODE | Should -Not -Be 0
    }

    AfterAll {
        Remove-Item -LiteralPath $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'verify-release.ps1 — missing SHA256SUMS' {
    BeforeAll {
        $script:tempDir = Join-Path ([IO.Path]::GetTempPath()) ("cct-verify-nosums-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:tempDir -Force | Out-Null
        # Deliberately do NOT create SHA256SUMS.
    }

    It 'errors when SHA256SUMS is missing' {
        { & $script:verifyPs1 -ReleaseDir $script:tempDir *> $null } |
            Should -Throw -ExpectedMessage 'SHA256SUMS not found*'
    }

    AfterAll {
        Remove-Item -LiteralPath $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

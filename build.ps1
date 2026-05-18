<#
.SYNOPSIS
    One-stop entry point for building, signing, testing, and verifying a
    Claude Code Install Manager release.

.DESCRIPTION
    Wraps the lower-level scripts under scripts/. Defaults to an unsigned
    local build that runs the Pester test suite and the user-side
    verify-release.ps1 against its own output.

    For a signed release, pass either -CertPath / -CertPassword (PFX on
    disk) or -Thumbprint (cert in Cert:\CurrentUser\My, for EV certs in
    a hardware token).

.PARAMETER OutDir
    Release directory. Defaults to release/dist.

.PARAMETER CertPath
    Path to a .pfx code-signing certificate. Implies -Sign.

.PARAMETER CertPassword
    SecureString PFX password. Prompted if -CertPath is given without
    -CertPassword.

.PARAMETER Thumbprint
    SHA1 thumbprint of a code-signing cert in Cert:\CurrentUser\My.
    Implies -Sign.

.PARAMETER TimestampUrl
    RFC 3161 timestamp server. Defaults to DigiCert's.

.PARAMETER SkipTests
    Don't run Pester tests. Default: tests run.

.PARAMETER SkipVerify
    Don't run verify-release.ps1 on the output. Default: verify runs.

.PARAMETER Clean
    Wipe OutDir before building.

.EXAMPLE
    # Local unsigned dev build with tests + verify.
    .\build.ps1

.EXAMPLE
    # Signed release using a PFX.
    .\build.ps1 -CertPath C:\certs\simtabi-codesign.pfx -CertPassword (Read-Host -AsSecureString)

.EXAMPLE
    # Signed release using a thumbprint (EV cert).
    .\build.ps1 -Thumbprint 1234ABCD5678EF901234ABCD5678EF901234ABCD

.EXAMPLE
    # CI usage: build unsigned, skip Pester (run separately), still verify.
    .\build.ps1 -SkipTests -Clean
#>
[CmdletBinding(DefaultParameterSetName = 'Unsigned')]
param(
    [string] $OutDir = (Join-Path $PSScriptRoot 'release/dist'),

    [Parameter(ParameterSetName = 'Pfx', Mandatory)]
    [string] $CertPath,

    [Parameter(ParameterSetName = 'Pfx')]
    [System.Security.SecureString] $CertPassword,

    [Parameter(ParameterSetName = 'Thumbprint', Mandatory)]
    [string] $Thumbprint,

    [string] $TimestampUrl = 'http://timestamp.digicert.com',

    [switch] $SkipTests,
    [switch] $SkipVerify,
    [switch] $Clean
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3

$repoRoot   = $PSScriptRoot
$scriptsDir = Join-Path $repoRoot 'scripts'
$buildPs1   = Join-Path $scriptsDir 'build-launcher.ps1'
$verifyPs1  = Join-Path $scriptsDir 'verify-release.ps1'
$testsDir   = Join-Path $scriptsDir 'tests'

function Step([string] $msg) {
    Write-Host ''
    Write-Host "==> $msg" -ForegroundColor Cyan
}

# ---- Clean -----------------------------------------------------------------
if ($Clean -and (Test-Path -LiteralPath $OutDir)) {
    Step "Cleaning $OutDir"
    Remove-Item -LiteralPath $OutDir -Recurse -Force
}

# ---- Tests -----------------------------------------------------------------
if (-not $SkipTests) {
    Step "Running Pester tests"
    $pester = Get-Module -ListAvailable -Name Pester |
              Sort-Object Version -Descending |
              Select-Object -First 1
    if (-not $pester) {
        Write-Warning "Pester not installed. Skipping tests. Install with:"
        Write-Warning "    Install-Module -Name Pester -Scope CurrentUser -Force"
    } else {
        Import-Module Pester -MinimumVersion 5.0
        $config = New-PesterConfiguration
        $config.Run.Path = $testsDir
        $config.Run.Exit = $false
        $config.Output.Verbosity = 'Detailed'
        $config.TestResult.Enabled = $false
        $result = Invoke-Pester -Configuration $config
        if ($result.FailedCount -gt 0) {
            throw "$($result.FailedCount) Pester test(s) failed."
        }
    }
}

# ---- Build -----------------------------------------------------------------
Step "Building launcher"
$buildArgs = @{
    OutDir       = $OutDir
    TimestampUrl = $TimestampUrl
}
switch ($PSCmdlet.ParameterSetName) {
    'Pfx' {
        $buildArgs['CertPath'] = $CertPath
        if ($CertPassword) { $buildArgs['CertPassword'] = $CertPassword }
    }
    'Thumbprint' {
        $buildArgs['Thumbprint'] = $Thumbprint
    }
    'Unsigned' {
        $buildArgs['SkipSign'] = $true
    }
}
& $buildPs1 @buildArgs

# ---- Verify ----------------------------------------------------------------
if (-not $SkipVerify) {
    Step "Verifying output"
    & $verifyPs1 -ReleaseDir $OutDir
    if ($LASTEXITCODE -ne 0) {
        throw "verify-release.ps1 reported a problem (exit $LASTEXITCODE)."
    }
}

Step "Done"
Write-Host "Release directory: $OutDir" -ForegroundColor Green
Get-ChildItem -LiteralPath $OutDir | Format-Table Name, Length, LastWriteTime | Out-Host

<#
.SYNOPSIS
    Verify a downloaded claude-code-install-manager release: SHA256 against SHA256SUMS,
    and Authenticode signature on claude-code-install-manager.exe (when present).

.DESCRIPTION
    Run this in the directory where you extracted the release. The script:

      1. Reads SHA256SUMS line-by-line and re-hashes every file it references.
      2. Reports each file as OK or BAD.
      3. If claude-code-install-manager.exe is present, runs `signtool verify /pa` (or,
         if signtool is unavailable, the .NET Authenticode API) and reports
         the publisher.
      4. Exits non-zero on any mismatch or signature failure, so the script
         is safe to call from CI.

    Nothing is installed or written to PATH. This is a read-only check.

.PARAMETER ReleaseDir
    Directory containing the release artifacts. Defaults to the script's own
    directory (so dropping verify-release.ps1 next to the release files and
    double-clicking works).

.PARAMETER AllowUnsigned
    Treat an unsigned (`NotSigned`) Authenticode status as a warning, not a
    failure. Used by CI and by the unsigned-fallback path of the release
    workflow. Released artifacts intended for distribution should always
    be signed; do not pass this flag when verifying a real shipped release.

.EXAMPLE
    .\verify-release.ps1

.EXAMPLE
    .\verify-release.ps1 -ReleaseDir C:\Downloads\claude-code-install-manager-0.1.0

.EXAMPLE
    # CI / local dev — accept an unsigned EXE.
    .\verify-release.ps1 -AllowUnsigned
#>
[CmdletBinding()]
param(
    [string] $ReleaseDir = $PSScriptRoot,
    [switch] $AllowUnsigned
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3

function Write-Section($text) {
    Write-Host ''
    Write-Host "==> $text" -ForegroundColor Cyan
}

function Write-Ok($text)   { Write-Host "    OK  $text" -ForegroundColor Green }
function Write-Bad($text)  { Write-Host "    BAD $text" -ForegroundColor Red }
function Write-Warn($text) { Write-Host "    !!  $text" -ForegroundColor Yellow }

if (-not (Test-Path -LiteralPath $ReleaseDir)) {
    throw "Release directory not found: $ReleaseDir"
}
$ReleaseDir = (Resolve-Path -LiteralPath $ReleaseDir).Path

Write-Section "Release directory"
Write-Host "    $ReleaseDir"

# ---------- SHA256SUMS check -------------------------------------------------
Write-Section "SHA256 check"
$sumsFile = Join-Path $ReleaseDir 'SHA256SUMS'
if (-not (Test-Path -LiteralPath $sumsFile)) {
    throw "SHA256SUMS not found in $ReleaseDir. The release is incomplete."
}

$mismatches = 0
$missing    = 0
$checked    = 0
Get-Content -LiteralPath $sumsFile | ForEach-Object {
    $line = $_.Trim()
    if (-not $line)             { return }
    if ($line.StartsWith('#'))  { return }

    # Expected format: "<64 hex chars>  <filename>" (two spaces)
    if ($line -notmatch '^([0-9a-fA-F]{64})\s+(.+)$') {
        Write-Warn "Skipping malformed line: $line"
        return
    }
    $expected = $matches[1].ToLower()
    $name     = $matches[2].Trim()
    $path     = Join-Path $ReleaseDir $name

    if (-not (Test-Path -LiteralPath $path)) {
        Write-Bad "$name (missing)"
        $missing++
        return
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
    if ($actual -eq $expected) {
        Write-Ok "$name"
    } else {
        Write-Bad "$name"
        Write-Host "        expected: $expected"
        Write-Host "        actual:   $actual"
        $mismatches++
    }
    $checked++
}

if ($checked -eq 0) {
    Write-Warn "SHA256SUMS was empty."
}

# ---------- Authenticode check ----------------------------------------------
Write-Section "Authenticode signature"
$exe = Join-Path $ReleaseDir 'claude-code-install-manager.exe'
$sigOk = $true
if (Test-Path -LiteralPath $exe) {
    $sig = Get-AuthenticodeSignature -LiteralPath $exe
    Write-Host "    Status:   $($sig.Status)"
    if ($sig.SignerCertificate) {
        Write-Host "    Subject:  $($sig.SignerCertificate.Subject)"
        Write-Host "    Issuer:   $($sig.SignerCertificate.Issuer)"
        Write-Host "    Valid:    $($sig.SignerCertificate.NotBefore) .. $($sig.SignerCertificate.NotAfter)"
        Write-Host "    Thumb:    $($sig.SignerCertificate.Thumbprint)"
    }
    if ($sig.TimeStamperCertificate) {
        Write-Host "    Timestamp: $($sig.TimeStamperCertificate.Subject)"
    } else {
        Write-Warn "Signature is not timestamped. It will become invalid when the cert expires."
    }

    if ($sig.Status -eq 'Valid') {
        Write-Ok "Signature is valid."
    } elseif ($sig.Status -eq 'NotSigned' -and $AllowUnsigned) {
        Write-Warn "Binary is not signed (NotSigned). Allowed by -AllowUnsigned."
        Write-Warn "Released artifacts intended for distribution should be signed."
    } else {
        Write-Bad "Signature status is '$($sig.Status)'."
        $sigOk = $false
    }
} else {
    Write-Warn "claude-code-install-manager.exe not present — skipping signature check."
    Write-Warn "If you only have the .cmd, signature verification is not possible."
    Write-Warn "(.cmd files cannot be Authenticode-signed.)"
}

# ---------- Mark of the Web --------------------------------------------------
Write-Section "Mark of the Web"
$motwHits = 0
foreach ($f in Get-ChildItem -LiteralPath $ReleaseDir -File) {
    $stream = Get-Item -LiteralPath $f.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue
    if ($stream) {
        Write-Warn "$($f.Name) carries Mark of the Web (downloaded from internet)."
        Write-Warn "  Unblock with: Unblock-File -Path '$($f.FullName)'"
        $motwHits++
    }
}
if ($motwHits -eq 0) {
    Write-Ok "No Mark-of-the-Web streams found."
}

# ---------- Summary ----------------------------------------------------------
Write-Section "Result"
$failed = ($mismatches + $missing) -gt 0 -or -not $sigOk
if ($failed) {
    Write-Host "    FAILED — see messages above." -ForegroundColor Red
    exit 1
}
Write-Host "    Release looks good." -ForegroundColor Green
exit 0

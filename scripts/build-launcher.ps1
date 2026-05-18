<#
.SYNOPSIS
    Build (and optionally Authenticode-sign) claude-code-install-manager.exe — a thin
    launcher that runs claude-code-install-manager.cmd from the same directory.

.DESCRIPTION
    Compiles scripts/launcher.cs into release/dist/claude-code-install-manager.exe using
    the .NET Framework C# compiler shipped with Windows itself (csc.exe under
    %WINDIR%\Microsoft.NET\Framework64\v4.0.30319\). No external SDK is
    required for an unsigned build.

    Signing options (mutually exclusive):
      * -CertPath / -CertPassword : sign with a PFX on disk.
      * -Thumbprint               : sign with a cert already in
                                    Cert:\CurrentUser\My (recommended for CI
                                    machines holding a hardware-bound EV cert).

    After building, the script writes release/dist/SHA256SUMS containing the
    post-signing hashes of every artifact, and copies claude-code-install-manager.cmd
    next to the EXE so the launcher can find it.

.PARAMETER OutDir
    Where build artifacts go. Defaults to ../release/dist relative to this
    script.

.PARAMETER CertPath
    Path to a .pfx code-signing certificate.

.PARAMETER CertPassword
    SecureString password for the PFX. If omitted with -CertPath, you will
    be prompted.

.PARAMETER Thumbprint
    SHA1 thumbprint of a code-signing certificate in
    Cert:\CurrentUser\My. Use this when the private key is held by an HSM /
    smart card (EV certs).

.PARAMETER TimestampUrl
    RFC 3161 timestamp server. Defaults to DigiCert's, which is free and
    widely trusted. A timestamp lets the signature stay valid after the
    cert itself expires.

.PARAMETER Description
    Friendly name embedded in the Authenticode signature ("Publisher" /
    "More info" fields in the SmartScreen dialog).

.PARAMETER ProductUrl
    URL embedded in the Authenticode signature (shown as a clickable link in
    the SmartScreen / Properties dialog).

.PARAMETER SkipSign
    Force an unsigned build even if signing parameters are set. Useful when
    iterating locally.

.EXAMPLE
    # Unsigned dev build.
    .\scripts\build-launcher.ps1

.EXAMPLE
    # Signed release using a PFX on disk.
    $pwd = Read-Host -AsSecureString
    .\scripts\build-launcher.ps1 -CertPath C:\certs\simtabi-codesign.pfx -CertPassword $pwd

.EXAMPLE
    # Signed release using an EV cert in the user store.
    .\scripts\build-launcher.ps1 -Thumbprint 1234ABCD5678EF901234ABCD5678EF901234ABCD

.NOTES
    Tested against the C# compiler shipped with .NET Framework 4.8 (Windows
    10/11 ships with this by default). If csc.exe is not on PATH, the script
    looks for it under %WINDIR%\Microsoft.NET\Framework64\v4.0.30319\.

    Signtool: located via PATH, then Windows SDK install root
    (%ProgramFiles(x86)%\Windows Kits\10\bin\*\x64\signtool.exe).

    Why a separate EXE: a .cmd file has no Authenticode signature block.
    Windows can only Authenticode-sign formats with a host-defined signature
    slot (PE, .ps1, .cab, .cat, .msi, ...). A PE launcher is the smallest
    such format we can ship that gives users a SmartScreen-friendly first
    impression.
#>
[CmdletBinding(DefaultParameterSetName = 'Unsigned')]
param(
    [string] $OutDir = (Join-Path $PSScriptRoot '..\release\dist'),

    [Parameter(ParameterSetName = 'Pfx', Mandatory)]
    [string] $CertPath,

    [Parameter(ParameterSetName = 'Pfx')]
    [System.Security.SecureString] $CertPassword,

    [Parameter(ParameterSetName = 'Thumbprint', Mandatory)]
    [string] $Thumbprint,

    [string] $TimestampUrl = 'http://timestamp.digicert.com',

    [string] $Description = 'Claude Code Install Manager for Windows',

    [string] $ProductUrl = 'https://github.com/simtabi',

    [switch] $SkipSign
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3

function Write-Section($text) {
    Write-Host ''
    Write-Host "==> $text" -ForegroundColor Cyan
}

function Find-Csc {
    $cmd = Get-Command csc.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Path }

    $candidates = @(
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    throw 'csc.exe not found. Install .NET Framework 4.x (shipped by default on Windows 10/11) or add csc.exe to PATH.'
}

function Find-SignTool {
    $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Path }

    $roots = @(
        ${env:ProgramFiles(x86)},
        $env:ProgramFiles
    ) | Where-Object { $_ }

    foreach ($root in $roots) {
        $base = Join-Path $root 'Windows Kits\10\bin'
        if (-not (Test-Path -LiteralPath $base)) { continue }
        $found = Get-ChildItem -LiteralPath $base -Recurse -Filter 'signtool.exe' -ErrorAction SilentlyContinue |
                 Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
                 Sort-Object FullName -Descending |
                 Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}

function Convert-SecureStringPlain([System.Security.SecureString] $s) {
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Hash-File($path) {
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
}

# ---------- Resolve paths ----------------------------------------------------
$repoRoot   = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$launcherCs = Join-Path $PSScriptRoot 'launcher.cs'
$cmdFile    = Join-Path $repoRoot 'claude-code-install-manager.cmd'

if (-not (Test-Path -LiteralPath $launcherCs)) { throw "Missing source: $launcherCs" }
if (-not (Test-Path -LiteralPath $cmdFile))    { throw "Missing .cmd: $cmdFile" }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path
$outExe = Join-Path $OutDir 'claude-code-install-manager.exe'

# ---------- Compile ----------------------------------------------------------
Write-Section "Compile launcher"
$csc = Find-Csc
Write-Host "Compiler: $csc"
Write-Host "Source:   $launcherCs"
Write-Host "Output:   $outExe"

# /win32manifest could embed a "requireAdministrator" manifest if we wanted UAC
# on every run; we deliberately do NOT, because Claude Code is per-user.
& $csc /nologo /optimize+ /platform:anycpu /target:exe `
       /out:"$outExe" `
       "$launcherCs"
if ($LASTEXITCODE -ne 0) { throw "csc failed with exit code $LASTEXITCODE" }

# ---------- Sign -------------------------------------------------------------
$signed = $false
if (-not $SkipSign -and $PSCmdlet.ParameterSetName -ne 'Unsigned') {
    Write-Section "Authenticode-sign launcher"
    $signtool = Find-SignTool
    if (-not $signtool) {
        throw 'signtool.exe not found. Install the Windows 10/11 SDK signing tools.'
    }
    Write-Host "Signtool: $signtool"

    $signArgs = @(
        'sign',
        '/fd', 'sha256',
        '/tr', $TimestampUrl,
        '/td', 'sha256',
        '/d',  $Description
    )
    if ($ProductUrl) { $signArgs += @('/du', $ProductUrl) }

    switch ($PSCmdlet.ParameterSetName) {
        'Pfx' {
            if (-not $CertPassword) {
                $CertPassword = Read-Host -Prompt "PFX password" -AsSecureString
            }
            $plain = Convert-SecureStringPlain $CertPassword
            try {
                $signArgs += @('/f', $CertPath, '/p', $plain)
                & $signtool @signArgs $outExe
            } finally {
                # Best effort to wipe the plaintext password from memory.
                $plain = $null
                [System.GC]::Collect()
            }
        }
        'Thumbprint' {
            $signArgs += @('/sha1', $Thumbprint, '/sm:no')
            & $signtool @signArgs $outExe
        }
    }
    if ($LASTEXITCODE -ne 0) { throw "signtool failed with exit code $LASTEXITCODE" }

    Write-Section "Verify signature"
    & $signtool verify /pa /v $outExe
    if ($LASTEXITCODE -ne 0) { throw "signtool verify failed: $LASTEXITCODE" }
    $signed = $true
} elseif ($SkipSign) {
    Write-Section "Sign skipped (-SkipSign)"
} else {
    Write-Section "Sign skipped (no cert provided)"
    Write-Host "This is an UNSIGNED build. SmartScreen will warn on first run." -ForegroundColor Yellow
    Write-Host "For a release build, pass -CertPath or -Thumbprint." -ForegroundColor Yellow
}

# ---------- Copy .cmd next to .exe ------------------------------------------
Write-Section "Stage release directory"
$cmdInDist = Join-Path $OutDir 'claude-code-install-manager.cmd'
Copy-Item -LiteralPath $cmdFile -Destination $cmdInDist -Force

# ---------- SHA256SUMS ------------------------------------------------------
Write-Section "Write SHA256SUMS"
$sumsFile = Join-Path $OutDir 'SHA256SUMS'
$artifacts = @($outExe, $cmdInDist)
$lines = foreach ($a in $artifacts) {
    $h = Hash-File $a
    $n = Split-Path -Leaf $a
    "$h  $n"
}
$lines | Set-Content -LiteralPath $sumsFile -Encoding ascii
Get-Content $sumsFile | Write-Host

# ---------- Summary ---------------------------------------------------------
Write-Section "Done"
Write-Host "Output directory: $OutDir"
Get-ChildItem -LiteralPath $OutDir | Format-Table Name, Length, LastWriteTime | Out-Host

if ($signed) {
    Write-Host ''
    Write-Host "Release artifacts are signed. Distribute the .exe AND the .cmd" -ForegroundColor Green
    Write-Host "(the .exe expects the .cmd next to it). Users who run the .exe"
    Write-Host "first see your publisher name in SmartScreen instead of a generic"
    Write-Host "'Unknown publisher' warning."
} else {
    Write-Host ''
    Write-Host "Unsigned build. Distribute claude-code-install-manager.cmd directly, OR" -ForegroundColor Yellow
    Write-Host "rebuild with -CertPath/-Thumbprint for a signed release."
}

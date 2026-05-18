# Changelog

All notable changes to this project are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — 2026-05-18

First public release.

### Added

#### Core tool — `claude-code-install-manager.cmd`

- `install` / `update` / `uninstall` / `repair` subcommands wrapping
  the official Claude Code installer at <https://claude.ai/install.ps1>.
- `doctor` subcommand with diagnostic checks for: OS / user / Windows
  / PowerShell version, privilege level, install location, version,
  PATH state in User and Machine scopes, command resolution in the
  current session, all conflicting installs (with upstream-issue
  citations), Claude Desktop App execution-alias hijack, PowerShell
  execution policy across all four scopes (with a Group-Policy
  override callout), and Git Bash detection
  (`CLAUDE_CODE_GIT_BASH_PATH` + `where bash.exe`).
- `path` subcommand reporting executable, directory, install kind
  (`native` / `winget` / `legacy-native` / `npm` / `path-resolved`),
  PATH state, live `where claude` resolution, Desktop App alias
  presence, and every detected install candidate (active one
  marked `*`).
- `version`, `where`, `help` subcommands.
- `repair-system` subcommand (alias `--repair-system-profile`).
  Cleans Claude leftovers under
  `%SystemRoot%\System32\config\systemprofile\` from an accidental
  admin-elevated install. Re-launches itself via UAC if not
  elevated. Hard prefix-check refuses to touch any path outside
  that tree.
- `disable-desktop-alias` subcommand (alias `fix-alias`). Removes the
  Claude Desktop App's Windows App Execution Alias at
  `%LOCALAPPDATA%\Microsoft\WindowsApps\Claude.exe`. Tries
  `Remove-Item -Force` first, falls back to `takeown` + `icacls` +
  `del` when needed, and prints the Settings UI path because
  Windows regenerates the alias on the next desktop-app update.
- `:Spin "<label>" "<powershell expression>"` helper. Spawns the
  expression in a child PowerShell runspace inside the same host
  process, renders a single-line spinner (one frame every 120 ms)
  with `mm:ss` elapsed time using CR-based overwrite, then
  replaces it with `OK` / `FAIL` and total elapsed when done.
  Honors `--quiet` and `CCT_NO_SPIN` for non-interactive use.
  Applied to: installer download in `:RunInstaller`,
  install-directory removal in `uninstall`, and SYSTEM-profile
  cleanup in `repair-system`.
- Pause-on-exit wrapper. Detects double-click invocation via
  `%cmdcmdline%` containing the script basename and pauses with
  `Press any key to close this window` before exit. Set
  `CCT_NO_PAUSE=1` to suppress.
- Direct `HKCU\Environment` writes via PowerShell, preserving the
  registry value kind (`REG_EXPAND_SZ` by default, falls back to
  `REG_SZ` only if the original was `REG_SZ`). `WM_SETTINGCHANGE`
  broadcast after the write so other listening processes pick up
  the change without a reboot.
- ANSI-colored output respecting `NO_COLOR` and `TERM=dumb`. Early
  color stubs at the top of `:CCTRunMain` so pre-`:InitColors`
  errors never print literal `%CLR_ERR%`.
- Actionable next-step hints in every error path: PATH-write
  failures point at Group Policy and `doctor`; PATH-clean failures
  point at the System Properties UI; a present-but-broken
  `claude.exe` suggests `install --force`.
- Five known install locations are checked in priority order with a
  `:_FindCandidate` helper, including
  `%LOCALAPPDATA%\Microsoft\WinGet\Links\claude.exe` for WinGet
  installs. `%LOCALAPPDATA%\Microsoft\WindowsApps\Claude.exe` is
  explicitly excluded from the `where claude` fallback because it
  resolves to the Claude Desktop App's execution alias, not the
  CLI.
- `uninstall` refuses to delete a WinGet-managed install and points
  at `winget uninstall Anthropic.ClaudeCode` instead.

#### Code signing pipeline

- `scripts/launcher.cs`: minimal .NET Framework 4.x C# launcher
  (`Simtabi.ClaudeCodeInstallManager.Launcher`) that re-execs the
  `.cmd` next to it via `cmd /c`, forwarding argv with proper
  quoting and propagating exit codes. The launcher exists because
  `.cmd` files cannot be Authenticode-signed; a signed PE wrapper
  is the canonical workaround.
- `scripts/build-launcher.ps1`: compiles via the built-in
  `csc.exe` shipped with Windows (no SDK needed for unsigned
  builds), Authenticode-signs with either a `-CertPath` PFX or a
  `-Thumbprint` from `Cert:\CurrentUser\My`, always passes `/tr`
  for RFC 3161 timestamping, verifies with `signtool verify /pa
  /v` after signing, writes `release/dist/SHA256SUMS` with
  post-sign hashes, and copies the `.cmd` alongside.
- `scripts/verify-release.ps1`: user-side verification. Hashes
  files against `SHA256SUMS`, runs `Get-AuthenticodeSignature` on
  the `.exe` (prints subject / issuer / validity range /
  thumbprint / timestamp status), scans for Mark-of-the-Web
  alternate data streams, exits non-zero on any failure.
- `build.ps1` (top-level entry): runs Pester tests, builds (signed
  or unsigned via parameter sets), verifies. `-Clean`,
  `-SkipTests`, `-SkipVerify` switches.

#### Tests + CI

- Pester 5 tests for `build-launcher.ps1` and `verify-release.ps1`
  under `scripts/tests/`. The verify-release tests synthesize fake
  release directories to exercise happy-path and corruption-
  detection branches without needing a real signed binary.
- `.github/workflows/ci.yml`: runs on push / PR / dispatch.
  Validates that `help` / `version` / `doctor` render, builds an
  unsigned release, runs Pester, uploads results.
- `.github/workflows/release.yml`: runs on `v*.*.*` tag push.
  Enforces `CHANGELOG.md` has the version, auto-detects signing
  mode (PFX-from-secret vs Azure Trusted Signing), builds, signs,
  verifies, zips, and creates the GitHub Release.

#### Repo scaffolding

- `LICENSE` (MIT, Copyright (c) 2026 Simtabi LLC) sourced from
  SPDX.
- `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1) sourced from
  EthicalSource, contact set to `opensource@simtabi.com`.
- `CONTRIBUTING.md`, `SECURITY.md`, `.editorconfig`, `.gitignore`,
  `.gitattributes`.
- Dependabot config: weekly Monday 06:00 America/New_York for
  GitHub Actions in `/` and `/.github/workflows`.
- Issue templates: bug report (requires `doctor` output and
  install-method dropdown), feature request (pushes "describe the
  problem first"), config (disables blank issues, routes upstream
  Claude Code bugs out of repo).
- Pull request template mirroring the CONTRIBUTING.md checklist.
- Release notes template with stable Artifacts / Verifying /
  Upgrading sections.

[Unreleased]: https://github.com/laranail/claude-code-install-manager/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/laranail/claude-code-install-manager/releases/tag/v0.1.0

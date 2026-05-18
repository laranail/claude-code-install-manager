# Contributing to Claude Code Install Manager

Thanks for considering a contribution. This project is a Windows-only
batch script plus a small C# launcher and PowerShell tooling; the
contribution surface area is small, the failure modes are subtle, and
most useful patches come from people who have hit a real problem.

## What to file vs. what to PR

| Situation                                                       | Open                 |
|-----------------------------------------------------------------|----------------------|
| `claude` not found after install, or `doctor` reports something weird | Issue — include `doctor` output  |
| Bug in the wrapper's PATH handling, install detection, etc.     | Issue, then PR if you have a fix |
| A new upstream `anthropics/claude-code` failure mode we should handle | Issue — link the upstream ticket |
| Typo, doc clarification, comment fix                            | PR                   |
| Cosmetic refactor without a behavior change                     | Don't — see "scope"  |

## Scope

The wrapper exists to paper over real, documented upstream issues
(see the **Known upstream issues** table in `README.md`). New
features should map to a specific, citable problem. Cosmetic
refactors, premature abstractions, and "while I was in here" cleanup
PRs are politely declined.

## Local dev setup

You need a Windows 10 or 11 machine (or VM) to actually test the
script. PowerShell 5.1 ships in-box; nothing else is required for
unsigned local builds. For signed releases you additionally need:

- Windows 10/11 SDK signing tools (`signtool.exe`)
- A code-signing certificate as `.pfx` (or in
  `Cert:\CurrentUser\My` referenced by thumbprint, recommended
  pattern for EV certs on a hardware token).

To run the script in-place after editing:

    .\claude-code-install-manager.cmd help
    .\claude-code-install-manager.cmd doctor

To build the launcher:

    .\scripts\build-launcher.ps1          # unsigned dev build
    .\scripts\build-launcher.ps1 -CertPath C:\certs\codesign.pfx -CertPassword (Read-Host -AsSecureString)

To verify a built release:

    .\scripts\verify-release.ps1 -ReleaseDir .\release\dist

## Conventions

### Batch script

- Two-space indent for `if` / `for` bodies. Four-space for routine
  bodies (matches the existing file).
- Always `set "VAR=value"` (with quotes around the assignment) to
  avoid trailing-whitespace bugs.
- Always use **delayed expansion** (`!VAR!`) inside parenthesized
  blocks. The script enables it at the top.
- Every routine ends with `goto :EOF` or `exit /b N`. Don't fall
  through into the next label.
- Cross-label flow: `call :Sub` for invocation that should return;
  `goto :Label` for one-way jumps. Mixing the two for the same label
  is a footgun — when both code paths end up at the same destination
  label, that label runs twice. Always reach for `goto` when the
  routine you're calling already ends with another `goto`.
- Error paths must use `:LogErr`, must include a next-step hint, and
  must `exit /b 1` (or higher).
- Cite upstream issues in code comments when adding a new code path
  to handle an upstream bug.

### PowerShell

- `Set-StrictMode -Version 3`.
- `$ErrorActionPreference = 'Stop'`.
- Functions PascalCased; variables camelCased.
- Avoid aliases (`?`, `%`, `gci`, etc.) in committed scripts; in the
  spinner we accept them because they fit on one line and run inside
  a runspace, not directly.

### C# (launcher)

- Stay on .NET Framework 4.x — the launcher must build with the
  in-box `csc.exe`. No external NuGet packages.
- Single file, single class. The launcher is intentionally trivial.

## Testing changes

There is no full automated test suite (cmd is hard to unit-test in
isolation). Before opening a PR:

1. Run `claude-code-install-manager.cmd help` and confirm formatting
   is intact.
2. Run `claude-code-install-manager.cmd doctor` on at least one
   machine that has Claude Code installed and one that doesn't.
3. If your change touches PATH handling, before and after:
   - Note `[Environment]::GetEnvironmentVariable('Path','User')` value.
   - Note `where claude` output.
4. If your change touches the spinner, run with and without
   `CCT_NO_SPIN=1` to confirm both paths still work.
5. If your change touches `repair-system`, test on a machine where
   `C:\Windows\System32\config\systemprofile\.local\bin\` does NOT
   exist, to confirm the no-op path. Don't fabricate the leftover by
   hand to test the cleanup path — install Claude Code as
   Administrator (in a VM) to produce a real one.
6. If your change touches `disable-desktop-alias`, you need the
   Claude Desktop App installed to produce the alias.

## Commits

- Subject in imperative mood, ≤ 72 characters.
- Body explains the **why**, not the **what**. The diff already shows
  the what.
- No emoji. No `Co-Authored-By:` trailers unless explicitly
  requested.
- Avoid AI-tell vocabulary in messages: `leverage`, `powerful`,
  `robust`, `comprehensive`, `seamless`, `essentially`, `simply`,
  `note that`.

## Pull request checklist

- [ ] Branch is up to date with `main`.
- [ ] `CHANGELOG.md` has an `[Unreleased]` entry under the appropriate
      section (Added / Changed / Fixed / Deprecated / Removed /
      Security).
- [ ] No new dependencies on tools that don't ship with Windows.
- [ ] `claude-code-install-manager.cmd help` and `doctor` still work
      and look right.
- [ ] If you added a new subcommand: it appears in `help`, has a row
      in the README **Subcommands** table, and follows the
      `:CmdXxx` naming convention.
- [ ] If you added a new external upstream-issue reference: it's
      linked in the **Known upstream issues** table in `README.md`.

## Security

For vulnerability disclosure, see [SECURITY.md](SECURITY.md). Do not
open public issues for security problems.

## Code of conduct

Project participation is governed by the
[Contributor Covenant 2.1](CODE_OF_CONDUCT.md). Enforcement contact:
`opensource@simtabi.com`.

## License

Contributions are accepted under the [MIT License](LICENSE).

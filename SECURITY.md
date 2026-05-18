# Security Policy

## Reporting a vulnerability

Email **`opensource@simtabi.com`**. If you require encryption, request
a PGP key in your first message and one will be sent in reply.

**Do not open a public GitHub issue, pull request, or discussion
thread for a security problem.** Public disclosure before a fix is
available exposes every user of the wrapper to the same risk.

When reporting, please include — to the extent you can:

- A description of the vulnerability and the attacker capability it
  enables (local user / remote user / network / supply chain).
- A minimal reproducer (commands, environment, expected vs.
  observed behavior).
- The version of `claude-code-install-manager.cmd` you tested
  against (`claude-code-install-manager.cmd version`).
- Whether you have already shared this finding with anyone else.

## Scope

In scope:

- The batch script `claude-code-install-manager.cmd`.
- The launcher `claude-code-install-manager.exe` produced by
  `scripts/build-launcher.ps1`.
- The supporting PowerShell scripts under `scripts/`.

Out of scope (please report to the relevant upstream project):

- Bugs in the official Claude Code installer (`install.ps1` hosted by
  Anthropic at <https://claude.ai/install.ps1>). Report to
  [anthropics/claude-code](https://github.com/anthropics/claude-code/issues).
- Bugs in `claude.exe` itself or its dependencies.
- Bugs in PowerShell, signtool, the Windows registry, or `csc.exe`.
- Bugs in third-party code-signing certificates or timestamp servers.

## What we treat as security-relevant

- Path-traversal or symlink-following defects in the cleanup
  routines (`uninstall`, `repair-system`, `disable-desktop-alias`).
  `:_SystemProfileClean` is the highest-stakes routine because it
  runs elevated.
- Argument injection through `%cmdcmdline%`, environment variables,
  flag parsing, or call-site quoting in `:Spin` /
  `:_FindCandidate` / similar helpers.
- TOCTOU between install detection and PATH writes.
- Failure to validate input to PowerShell sub-invocations.
- Defects that would lead the wrapper to delete files outside the
  documented target set under any input.
- Defects that would cause the launcher (`claude-code-install-manager.exe`)
  to execute a `.cmd` other than the one shipped alongside it.

## What we do not treat as a vulnerability

- SmartScreen warnings on unsigned builds — that's the expected
  behavior. The signed `.exe` from a recognized publisher is the
  fix; see the **Releases and code signing** section of `README.md`.
- The wrapper refusing to delete a WinGet-managed install or the
  Claude Desktop App alias when the user invokes `uninstall` /
  `disable-desktop-alias` — those refusals are deliberate guards,
  not bugs.

## Disclosure process

Once we have confirmed a report:

1. We will acknowledge receipt within five business days.
2. We will keep the reporter informed of progress at least every two
   weeks until a fix ships or the report is closed.
3. We will coordinate a release window with the reporter and
   credit them in `CHANGELOG.md` and the GitHub release notes
   (unless the reporter prefers anonymity).
4. We do not currently operate a bug bounty.

## Supported versions

The latest tagged release is the only supported version. Older
versions do not receive backported fixes; upgrade.

| Version  | Supported       |
|----------|-----------------|
| 0.1.x    | Yes (current)   |

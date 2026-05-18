# Claude Code Install Manager

Install, update, repair, and diagnose [Claude Code](https://claude.com/claude-code)
on Windows. Single-file batch script (`claude-code-install-manager.cmd`) plus
an optional signed `.exe` launcher for SmartScreen-friendly distribution.

## Why this exists

Windows has no first-class package manager. The official Claude Code
installer (`irm https://claude.ai/install.ps1 | iex`) drops a binary
into a per-user directory and appends that directory to your User
PATH — and that's it. After that succeeds, the operating system
itself has no record that anything was installed:

- No entry in **Add or Remove Programs**.
- No MSI receipt, no AppX manifest, no Windows Installer database row.
- No canonical "where is `claude`" anyone can query.

You can install Claude Code, watch the installer say `Done`, and
then open a new cmd window where `claude` is "not recognized as an
internal or external command" — because the install location is
random across versions, the PATH change does not propagate to
already-open sessions, and nothing in the OS even knows the install
happened. There is no built-in way to update, repair, uninstall,
or diagnose.

That entire problem space is what this wrapper covers. On macOS,
Homebrew handles it. On Linux, the distro package manager handles
it. On Windows, you write a batch file.

This is that batch file.

## What it does

* `install`                Run the official installer and configure User PATH.
* `update`                 Re-run the installer to fetch the latest version.
* `uninstall`              Remove the install directory and clean User PATH.
* `repair`                 Fix PATH for an existing install (no reinstall).
* `repair-system`          Clean Claude leftovers under the SYSTEM profile (UAC-elevates).
* `disable-desktop-alias`  Remove the Claude Desktop App execution alias that shadows the CLI.
* `doctor`                 Diagnose install state, PATH, version, and conflicts.
* `path`                   Show install directory, install kind, PATH state, and all detected install candidates.
* `version`                Show wrapper and Claude Code versions.
* `where`                  Show where the `claude` command resolves from.
* `help`                   Print usage.

All write operations are idempotent. Running `install` twice does the right
thing. Running `repair` when nothing is broken is a no-op.

## Requirements

* Windows 10 or 11 (cmd, PowerShell 5.1+).
* Standard user account. Do not run as Administrator. Claude Code installs
  per-user; running elevated tends to land it under the SYSTEM profile.
* Network access to `https://claude.ai`.

## Install

1. Download `claude-code-install-manager.cmd` to a folder you can find again
   (for example `C:\Tools\claude-code-install-manager\`).
2. Optional but convenient: add that folder to your User PATH so you can
   run `claude-code-install-manager` from anywhere.
3. Open a regular Command Prompt or PowerShell window.
4. Run:

       claude-code-install-manager install

The script will run the official installer, detect where `claude.exe` landed,
add that directory to your User PATH, broadcast the environment change so
other applications notice, refresh PATH in the current shell, and verify the
binary runs.

## Usage

    claude-code-install-manager <subcommand> [flags]

### Subcommands

| Command                  | Purpose                                                          |
|--------------------------|------------------------------------------------------------------|
| `install`                | Install Claude Code (default if no subcommand given).            |
| `update`                 | Update to the latest version. Falls back to `install` if absent. |
| `uninstall`              | Remove the install directory and clean PATH entries.             |
| `repair`                 | Fix PATH for an existing install without reinstalling.           |
| `repair-system`          | Clean Claude leftovers under `C:\Windows\System32\config\systemprofile\` from an accidental admin-elevated install. Re-launches itself elevated via UAC. |
| `disable-desktop-alias`  | Remove `%LOCALAPPDATA%\Microsoft\WindowsApps\Claude.exe` so the Claude Desktop App stops hijacking the `claude` command. Tries Remove-Item first; falls back to `takeown + icacls + del` if needed. |
| `doctor`                 | Print a full diagnostic report.                                  |
| `path`                   | Show install location, install kind, PATH state in User and Machine scopes, `where claude` resolution, Desktop App alias presence, and every detected install candidate. |
| `version`                | Print wrapper version and `claude --version`.                    |
| `where`                  | Show where `claude` resolves from.                               |
| `help`                   | Show usage.                                                      |

Aliases: `upgrade` for `update`, `remove` for `uninstall`, `fix` for `repair`,
`--repair-system-profile` for `repair-system`, `fix-alias` for
`disable-desktop-alias`, `check` for `doctor`, `which` for `where`,
`--help` and `-h` for `help`.

### Flags

Flags must appear after the subcommand.

| Flag                 | Purpose                                                  |
|----------------------|----------------------------------------------------------|
| `--force`, `-f`      | Proceed despite warnings; reinstall if already present.  |
| `--yes`, `-y`        | Auto-confirm prompts (admin warning, uninstall confirm). |
| `--quiet`, `-q`      | Suppress informational output. Errors still print.       |
| `--verbose`, `-v`    | Extra debug output.                                      |
| `--download-only`    | Download installer to `%TEMP%`, show SHA256, do not run. |

### Environment variables

| Variable        | Effect                                                                  |
|-----------------|-------------------------------------------------------------------------|
| `CCT_NO_PAUSE`  | If set (any value), skip the "Press any key to close" pause on exit.   |
| `CCT_NO_SPIN`   | If set (any value), suppress the spinner shown during long operations. |

`--quiet` / `-q` also suppresses the spinner.

### Progress display

For operations that take more than ~1 second and are otherwise silent
— installer download, install-directory removal during `uninstall`,
SYSTEM-profile cleanup during `repair-system` — the script renders a
single-line spinner with the elapsed time, refreshing every 120 ms:

    [|] Downloading installer from https://claude.ai/install.ps1  00:03

When the operation finishes, the spinner line is replaced in place with
an `OK` / `FAIL` line plus the total time:

    [OK  ] Downloading installer from https://claude.ai/install.ps1  (00:07)

Operations that already produce their own progress output (the upstream
Claude Code installer's own stdout, for instance) are deliberately not
wrapped in the spinner — that would buffer their output until the end.
Set `CCT_NO_SPIN=1` for plain text-only output (useful in CI or in
terminals that don't honor carriage-return-based overwrites).

## Examples

Install fresh:

    claude-code-install-manager install

Force a clean reinstall:

    claude-code-install-manager install --force

Update to the latest version:

    claude-code-install-manager update

Diagnose why `claude` is not working:

    claude-code-install-manager doctor

Fix PATH after a manual installer run that did not register correctly:

    claude-code-install-manager repair

Uninstall without prompts:

    claude-code-install-manager uninstall --yes

Inspect the installer script before running it:

    claude-code-install-manager install --download-only

This prints the SHA256 hash and saved path. Open the `.ps1` file, review it,
then run it manually:

    powershell -ExecutionPolicy Bypass -File "%TEMP%\claude-installer-XXXX.ps1"

## What the wrapper fixes

The following are real issues encountered using the bare installer:

**`claude` not recognized after install.** The native installer writes to the
User PATH, but the current cmd or PowerShell session keeps its cached copy.
The wrapper refreshes PATH in the current session and broadcasts
`WM_SETTINGCHANGE` so other listening processes (Explorer, new terminals)
pick up the change without a reboot.

**Install location drift.** Four different paths can hold a working
`claude` binary, depending on which installer ran:

| Path                                                       | Source                          |
|------------------------------------------------------------|---------------------------------|
| `%USERPROFILE%\.local\bin\claude.exe`                      | Current native installer        |
| `%LOCALAPPDATA%\Microsoft\WinGet\Links\claude.exe`         | `winget install Anthropic.ClaudeCode` |
| `%LOCALAPPDATA%\Programs\claude\claude.exe` (and `bin\`)   | Older native installer          |
| `%APPDATA%\npm\claude.cmd`                                 | `npm install -g @anthropic-ai/claude-code` |

The wrapper checks all of them in that order and records which kind
of install it found. There is no canonical "where is `claude`" you
can ask Windows; this list is the answer.

**WinGet and native installer collide silently.** Running the
native installer when WinGet already installed Claude Code creates
two complete copies, neither aware of the other, with PATH order
deciding which one `claude` runs. Upstream:
[anthropics/claude-code#31980](https://github.com/anthropics/claude-code/issues/31980).
`doctor` reports both, and `uninstall` refuses to delete a
WinGet-managed copy (which would corrupt WinGet's package
database) and tells you to run `winget uninstall
Anthropic.ClaudeCode` instead.

**Claude Desktop App hijacks the `claude` command.** The desktop
app installs a Windows App Execution Alias at
`%LOCALAPPDATA%\Microsoft\WindowsApps\Claude.exe`. WindowsApps
typically sits high on PATH, so `claude` from a terminal launches
the Electron desktop app instead of the CLI — silently, with no
warning. Upstream:
[anthropics/claude-code#25075](https://github.com/anthropics/claude-code/issues/25075),
[#24903](https://github.com/anthropics/claude-code/issues/24903).
`doctor` reports the alias's presence; `install`, `update`, and
`repair` warn when their verification step sees `claude` resolving
to it. Disable in:  Settings → Apps → Advanced app settings → App
execution aliases.

**Stale PATH entries after uninstall.** Removing the binary by hand leaves
dead PATH entries. `uninstall` cleans them.

**Lost `REG_EXPAND_SZ` on PATH.** Some tools write PATH back as `REG_SZ`,
breaking `%VAR%` expansion for other entries. The wrapper preserves the
original registry value kind.

**Silent admin-elevation footgun.** Running the installer as Administrator
puts files under the SYSTEM profile, not yours. The wrapper warns before
proceeding.

**Console window closes before you can read it.** If you launch the
script by double-clicking it from Explorer, cmd opens, runs the script,
and slams the window shut. Any error message vanishes with it. The
wrapper detects double-click invocation (by inspecting `%cmdcmdline%`
for its own basename) and pauses with `Press any key to close...`
before exiting. Running from an existing terminal — where output stays
on screen — does not pause, so automation is not blocked. Set
`CCT_NO_PAUSE=1` to suppress the pause unconditionally.

**No diagnostics.** When something is wrong, the bare installer offers no
help. `doctor` reports:

- OS, user, Windows version, PowerShell version.
- Privilege level (admin or standard user).
- Install location (which of the four paths, and its detected "kind").
- Installed version.
- PATH status in both User and Machine scopes.
- Command resolution from the current session.
- All conflicting installs (with the upstream issue reference).
- Claude Desktop App execution-alias hijack check.
- PowerShell execution policy across all scopes, with a flag if
  `MachinePolicy` or `UserPolicy` is set by Group Policy (which
  overrides `Set-ExecutionPolicy`).
- Git Bash detection — `CLAUDE_CODE_GIT_BASH_PATH` value if set,
  otherwise `where bash.exe`. Claude Code's Bash tool requires
  Git Bash on Windows; the absence of either is a real failure
  mode ([#3461](https://github.com/anthropics/claude-code/issues/3461),
  [#25593](https://github.com/anthropics/claude-code/issues/25593)).
- Config-directory presence.

**Unhelpful error output.** Common failure paths now include a
next-step hint — PATH-write failures point at group policy and at
`doctor`; a present-but-broken `claude.exe` suggests reinstall under
`--force`; PATH-clean failures point at the manual System Properties
fallback.

## How PATH is handled

### Lookup order

When any subcommand needs to know "where is `claude`", the wrapper
checks five paths in this order and records the *kind* of install
it found:

1. `%USERPROFILE%\.local\bin\claude.exe` — `native`
2. `%LOCALAPPDATA%\Microsoft\WinGet\Links\claude.exe` — `winget`
3. `%LOCALAPPDATA%\Programs\claude\claude.exe` — `legacy-native`
4. `%LOCALAPPDATA%\Programs\claude\bin\claude.exe` — `legacy-native`
5. `%APPDATA%\npm\claude.cmd` — `npm`

If none match, the wrapper falls back to `where claude` — but with
`%LOCALAPPDATA%\Microsoft\WindowsApps\Claude.exe` explicitly
filtered out, since that path resolves to the Claude Desktop App's
execution alias, not the CLI.

`claude-code-install-manager path` prints all five candidates (marking the
active one with `*`), the install kind, User and Machine PATH
state, what `where claude` currently resolves to, and a warning if
the Desktop App alias is present.

### Adding to PATH

The wrapper writes directly to `HKCU\Environment` via PowerShell,
preserving the existing value kind (`REG_EXPAND_SZ` by default,
falling back to `REG_SZ` only if the original was `REG_SZ`). After
the registry write it broadcasts `WM_SETTINGCHANGE` with
`lParam = "Environment"` to notify other running processes. Newly
launched processes will see the change immediately; already-running
ones depend on whether they listen for the broadcast (most shells
do not, which is why VS Code or an existing cmd window must be
restarted).

Why not `setx`? `setx` truncates values at 1024 characters,
silently corrupting long PATHs. The wrapper avoids it for that
reason.

### Removing from PATH

`uninstall` cleans these directories from the User PATH:

- `%USERPROFILE%\.local\bin`
- `%LOCALAPPDATA%\Programs\claude`
- `%LOCALAPPDATA%\Programs\claude\bin`

The WinGet `Links` directory is **not** cleaned, because it's
shared by every WinGet-managed CLI on the system. The npm prefix
is also not cleaned, for the same reason. If Claude Code was
installed via either of those, `uninstall` refuses (for WinGet) or
leaves the PATH entry alone (for npm) — you remove the install
through its native package manager.

## Privileges

This is a per-user tool. Every operation except `repair-system` (and the
admin-fallback path of `disable-desktop-alias`) runs as a standard user.
The wrapper writes only to `HKCU\Environment`; it never touches `HKLM`,
`C:\Program Files`, system services, or anything outside the current
user's profile.

`install`, `update`, `uninstall`, `repair`, `doctor`, `path`, `version`,
and `where` actively **refuse** to run as Administrator by default
(`:CheckAdmin` warns and aborts unless you pass `--yes` / `--force`).
That guard exists because running the upstream installer elevated
lands `claude.exe` under `C:\Windows\System32\config\systemprofile\` —
useless for the actual user. `repair-system` is the antidote for the
case where that already happened, and is the only subcommand that
intentionally calls UAC.

## Repair / cleanup subcommands

### `repair-system`

Removes Claude Code files left under the SYSTEM account's profile
after someone ran the bare installer elevated. The wrapper:

1. Detects whether the current process is elevated.
2. If not, asks for confirmation and re-launches itself via
   `Start-Process -Verb RunAs` (Windows shows the UAC prompt). The
   elevated re-launch passes `--yes` so the second window does not
   stall waiting for input.
3. In the elevated session, walks three known paths:
   * `%SystemRoot%\System32\config\systemprofile\.local\bin\claude.exe`
   * `%SystemRoot%\System32\config\systemprofile\AppData\Local\Programs\claude\`
   * `%SystemRoot%\System32\config\systemprofile\AppData\Roaming\npm\claude.cmd`
4. Refuses (with a hard substring check) to touch any path that does
   not start with `%SystemRoot%\System32\config\systemprofile\`, so a
   bug or a malicious `%SystemRoot%` override can't escape that tree.
5. Reports cleaned / failed counts.

You can run it directly:

    claude-code-install-manager repair-system --yes

or with the long alias the user might guess from the flag-style name:

    claude-code-install-manager --repair-system-profile

### `disable-desktop-alias`

Removes the Windows App Execution Alias the Claude Desktop App
installs at `%LOCALAPPDATA%\Microsoft\WindowsApps\Claude.exe`. The
alias is a reparse point owned by the AppX subsystem and refuses
ordinary delete operations, so the wrapper tries the cheap path
first and escalates only when needed:

1. `Remove-Item -Force` via PowerShell. Works on some Windows builds
   for files the user owns.
2. If that fails: re-prompts for admin (or errors out telling the
   user how to re-run elevated), then `takeown /f` + `icacls /grant`
   + `del /f /q`.
3. If even step 2 fails, prints the **only sticky fix**: open
   Settings → Apps → Advanced app settings → App execution aliases
   and toggle Claude off. Windows regenerates the alias on the next
   Claude Desktop App update, so the Settings toggle is the
   permanent answer even when the delete succeeds — the wrapper
   tells you this in both branches.

    claude-code-install-manager disable-desktop-alias --yes

## Security notes

* The script downloads from `https://claude.ai/install.ps1`. PowerShell
  validates TLS by default; no certificate pinning is done beyond that.
* Use `--download-only` to inspect the installer locally before execution.
  The SHA256 hash is printed so you can record or compare it.
* No credentials, tokens, or telemetry are sent by this wrapper. It only
  reads and writes your own `HKCU\Environment`, calls the official
  installer, and runs `claude --version` for verification.
* The wrapper never writes to `HKLM` or system directories.
* `uninstall` preserves `%USERPROFILE%\.claude\`. Configuration and
  conversation history are kept. Delete that directory manually for a
  full wipe.

## Troubleshooting

### `claude` is still not found after install

1. Close every terminal window (not just the tab; the whole window).
2. Open a new one and try again.
3. If still failing, run `claude-code-install-manager doctor` and look at the
   "PATH status" and "Command resolution" sections.

### Installer fails behind a corporate proxy

* Use `--download-only` to download via `Invoke-WebRequest`, which honors
  `$env:HTTPS_PROXY` more reliably, then run the saved script manually.
* If TLS inspection breaks the download, the proxy team needs to add an
  exception for `claude.ai`.

### "PowerShell execution policy" error

`-ExecutionPolicy Bypass` is set on every internal PowerShell call, so the
wrapper itself runs even under a restricted policy. If the installer
sub-script still fails, run from an elevated PowerShell briefly to confirm:

    Get-ExecutionPolicy -List

If `MachinePolicy` is `AllSigned` or stricter and is set by Group Policy,
your IT team controls this and you cannot override it from user space.

### Multiple installs reported by `doctor`

Pick the one you want to keep. Remove the others by deleting their parent
folders, then run `claude-code-install-manager repair` so PATH points to the survivor.

**Exception — WinGet-managed install:** don't delete it by hand.
Run `winget uninstall Anthropic.ClaudeCode` first, then
`claude-code-install-manager repair` (or `install` if you want the native
installer's copy). `uninstall` in this wrapper refuses to touch a
WinGet copy for this reason.

### `claude` launches the desktop app instead of the CLI

The Claude Desktop App installs a Windows App Execution Alias at
`%LOCALAPPDATA%\Microsoft\WindowsApps\Claude.exe` that can sit
higher on PATH than the CLI. `doctor` and `install/repair`
verification both flag this. To fix:

1. Open Settings → Apps → Advanced app settings → App execution aliases.
2. Find the Claude entry and toggle it off.
3. Open a fresh terminal.
4. `where claude` should now point at the CLI, not WindowsApps.

You can also remove the file directly, but Windows may regenerate
it on the next desktop-app update; the Settings toggle is sticky.

### Claude Code's Bash tool fails on Windows

Claude Code's `Bash` tool relies on Git Bash on Windows; it cannot
use Command Prompt or PowerShell as a shell. If the tool throws
"No suitable shell found" or "Raw mode is not supported", install
Git for Windows and either:

* Add `C:\Program Files\Git\bin\` to PATH, **or**
* Set `CLAUDE_CODE_GIT_BASH_PATH` to the full path of `bash.exe`.

`doctor` reports both states. Upstream references:
[#3461](https://github.com/anthropics/claude-code/issues/3461),
[#9883](https://github.com/anthropics/claude-code/issues/9883),
[#25593](https://github.com/anthropics/claude-code/issues/25593).

### Uninstall left some files behind

The most common cause is a running `claude` process holding a file open.
Close any terminals or editors that may have started a `claude` subprocess,
then re-run `claude-code-install-manager uninstall`.

### "Press any key to close" appears when I don't want it

The script pauses on exit when it thinks it was launched by
double-click. The detection inspects `%cmdcmdline%`; if you wrap the
script in `cmd /c "claude-code-install-manager ..."` from another shell, the
detection sees the basename and triggers a pause. Set
`CCT_NO_PAUSE=1` in the environment to disable the pause for the
entire process tree, or pass it inline:

    cmd /c "set CCT_NO_PAUSE=1 && claude-code-install-manager install"

## Known upstream issues this wrapper works around

For convenience, here is the list of `anthropics/claude-code`
issues that motivate specific code paths in `claude-code-install-manager.cmd`.
All are present in the official tracker as of May 2026.

| Issue                                                                                              | Symptom                                                                          | What the wrapper does                              |
|----------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------|----------------------------------------------------|
| [#3838](https://github.com/anthropics/claude-code/issues/3838)                                     | `claude` CLI not recognized after global install (Windows)                       | `install` + automatic PATH registration            |
| [#11358](https://github.com/anthropics/claude-code/issues/11358)                                   | Native installer doesn't add PATH                                                | `install` + `repair` write PATH directly to HKCU   |
| [#14942](https://github.com/anthropics/claude-code/issues/14942)                                   | Installer reports success but `claude.exe` is missing                            | `install` re-runs `FindClaude` after the installer and errors clearly if nothing landed |
| [#21365](https://github.com/anthropics/claude-code/issues/21365)                                   | Native `install.ps1` does not add installation directory to PATH                 | Same — `install` adds it itself                    |
| [#25075](https://github.com/anthropics/claude-code/issues/25075)                                   | Claude Desktop App installer hijacks the `claude` command                        | `doctor` and `install/repair` verification flag the alias path |
| [#24903](https://github.com/anthropics/claude-code/issues/24903)                                   | Desktop App execution alias shadows Claude Code CLI in PATH                      | Same                                              |
| [#31980](https://github.com/anthropics/claude-code/issues/31980)                                   | Native installer and WinGet install to different locations silently              | `doctor` lists both; `uninstall` refuses to delete WinGet's copy |
| [#27634](https://github.com/anthropics/claude-code/issues/27634)                                   | WinGet install doesn't set up the native install at `~/.local/bin`               | `install` from this wrapper uses the native installer's location |
| [#32098](https://github.com/anthropics/claude-code/issues/32098), [#41578](https://github.com/anthropics/claude-code/issues/41578) | False "PATH not set" warnings from the installer reading the wrong scope         | Wrapper queries the registry directly, not the inherited process PATH |
| [#42337](https://github.com/anthropics/claude-code/issues/42337)                                   | v2.1.89 regression: native installer succeeds but does not add `.local\bin`      | Same — wrapper handles PATH itself                  |
| [#3461](https://github.com/anthropics/claude-code/issues/3461), [#25593](https://github.com/anthropics/claude-code/issues/25593) | Claude Code requires Git Bash; "No suitable shell found" without it              | `doctor` reports `CLAUDE_CODE_GIT_BASH_PATH` and `where bash.exe` |
| [#9883](https://github.com/anthropics/claude-code/issues/9883)                                     | Bash tool incompatible with MSYS / Git Bash (needs `cygpath`)                    | Documented; the wrapper can't fix the upstream tool but `doctor` surfaces the env |

Run `claude-code-install-manager doctor` to see which of these apply to your
machine right now.

## Releases and code signing

### Why a separate `.exe`

**`.cmd` and `.bat` files cannot be Authenticode-signed.** Windows'
signature subsystem can only sign formats that carry a host-defined
signature block:

| Format          | Signable | How signature is stored                |
|-----------------|----------|----------------------------------------|
| `.exe`, `.dll`  | yes      | PE certificate table                   |
| `.ps1`, `.psm1` | yes      | trailing `# SIG # Begin signature block` lines |
| `.msi`, `.cab`  | yes      | embedded                               |
| `.cat`          | yes      | embedded (catalog)                     |
| `.cmd`, `.bat`  | **no**   | no signature slot exists in the format |

There is no published technique to attach an Authenticode signature
to a `.cmd` file. SmartScreen sees an unsigned script and a
Mark-of-the-Web alternate data stream and warns the user. The
work-around used by every signed shell-script-style distribution
on Windows (Chocolatey, scoop, etc.) is the same one this project
uses: ship a tiny signed PE alongside the script.

### Build & sign — `scripts/build-launcher.ps1`

The build script compiles `scripts/launcher.cs` into
`release/dist/claude-code-install-manager.exe`, an Authenticode-signable
launcher that simply re-exec's `claude-code-install-manager.cmd` (from the
same directory) under `cmd.exe`, forwarding all arguments and
returning the script's exit code. Users who run the signed `.exe`
see the publisher name in the SmartScreen dialog instead of
"Unknown publisher".

The launcher uses `csc.exe` from .NET Framework 4.x (shipped with
every Windows 10 / 11 install), so there is no extra SDK dependency
to build it.

**Unsigned dev build:**

    .\scripts\build-launcher.ps1

**Signed release using a PFX on disk:**

    $pwd = Read-Host -AsSecureString
    .\scripts\build-launcher.ps1 -CertPath C:\certs\codesign.pfx -CertPassword $pwd

**Signed release using a thumbprint** (recommended for EV certs in
a hardware token, where the private key never touches disk):

    .\scripts\build-launcher.ps1 -Thumbprint 1234ABCD...

After signing, the script runs `signtool verify /pa /v` against the
output, writes `release/dist/SHA256SUMS` with post-sign hashes, and
copies `claude-code-install-manager.cmd` next to the EXE so the launcher can
find it.

### Verify — `scripts/verify-release.ps1`

Ship this alongside the release. Users (or CI) can run it to
confirm a download:

    .\verify-release.ps1

The script:

1. Reads `SHA256SUMS` and re-hashes every file it references.
2. Runs `Get-AuthenticodeSignature` on `claude-code-install-manager.exe` and
   prints the subject, issuer, validity dates, thumbprint, and
   timestamp status. Warns if the signature has no RFC 3161
   timestamp (which would make it expire with the cert).
3. Walks the release directory looking for `Zone.Identifier`
   alternate data streams (Mark-of-the-Web) and tells the user how
   to unblock them.
4. Exits non-zero on any mismatch.

### Costs and gotchas

* A standard code-signing cert costs roughly USD 200 / year. EV
  certs (which build SmartScreen reputation faster) are USD 300+.
* Without an EV cert, a fresh signed `.exe` still triggers
  "SmartScreen Filter prevented an unrecognized app from starting"
  on first launch until enough installs build reputation. Users
  can click "More info" → "Run anyway" once; subsequent launches
  on the same machine are silent.
* The build script always passes `/tr` (RFC 3161 timestamp). Do
  not remove this — without a timestamp, the signature stops
  validating the day the cert expires, even on existing downloads.
* Sign artifacts **before** publishing the SHA256SUMS file. The
  build script does this in the right order.

## Uninstalling the wrapper itself

The wrapper is a single file. Delete `claude-code-install-manager.cmd` and, if you
added its folder to PATH, remove that entry from User environment
variables.

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Simtabi LLC.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Vulnerability disclosure
lives in [SECURITY.md](SECURITY.md). Project participation is
governed by the [Contributor Covenant 2.1](CODE_OF_CONDUCT.md).

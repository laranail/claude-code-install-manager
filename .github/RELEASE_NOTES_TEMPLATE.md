<!--
Release notes for Claude Code Install Manager. The release.yml workflow
appends this template to GitHub's auto-generated release notes, which
list merged PRs since the last tag. Customize per-release in the
"Highlights" section below; leave the rest as a stable reminder of
what the artifacts are and how to use them.
-->

## Highlights

<!-- Pick the 2-4 most user-visible changes from CHANGELOG.md and put
     them here in plain prose. Link to anthropics/claude-code issues
     for the ones that fix an upstream problem. -->

## Artifacts

| File                                       | Contents                                              |
|--------------------------------------------|-------------------------------------------------------|
| `claude-code-install-manager.exe`          | Signed launcher. Run this if your org enforces SmartScreen / unsigned-binary policies. |
| `claude-code-install-manager.cmd`          | The actual wrapper. The `.exe` re-executes this from the same directory. |
| `SHA256SUMS`                               | Post-signing SHA256 hashes for both files.            |
| `claude-code-install-manager-vX.Y.Z-windows.zip` | All three above, bundled.                       |

Run `claude-code-install-manager.exe help` (or just the `.cmd`) to get
started.

## Verifying

Download `claude-code-install-manager.exe`, `claude-code-install-manager.cmd`,
and `SHA256SUMS` into one directory, then:

```powershell
# Optional: also grab verify-release.ps1 from the repo's scripts/ dir.
.\verify-release.ps1
```

Or check the signature manually:

```powershell
Get-AuthenticodeSignature .\claude-code-install-manager.exe |
    Format-List Status, SignerCertificate
```

You should see `Status : Valid` and a publisher subject containing
`Simtabi LLC`.

## Upgrading

This is a per-user tool. To upgrade in place:

1. Replace your existing `claude-code-install-manager.cmd` (and `.exe`
   if you have it) with the new files.
2. Run `claude-code-install-manager doctor` to confirm nothing
   regressed.

## Full change list

See [CHANGELOG.md](https://github.com/simtabi/claude-code-install-manager/blob/main/CHANGELOG.md).

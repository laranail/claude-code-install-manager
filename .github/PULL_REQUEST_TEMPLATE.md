<!--
Thanks for sending a PR. Please fill out the sections below. Anything
listed in CONTRIBUTING.md's "Pull request checklist" applies here too.
-->

## What this changes

<!-- One or two sentences. The diff already shows the *what*; explain
     the *why*. -->

## Motivation

<!-- What problem prompted the change? Link an upstream
     anthropics/claude-code issue if applicable. Real-world repro
     scenarios are persuasive. -->

## Scope

- [ ] This change maps to a real, documented problem (not a cosmetic
      refactor).
- [ ] The change is limited to the surface area named in the title.
- [ ] No new external dependencies that don't ship with Windows.

## Testing

<!-- Describe how you tested. Include the OS / shell / Claude Code
     install method on the test machine. The CI workflow handles the
     basic build + doctor + Pester checks; this section is for
     scenarios CI can't cover. -->

- [ ] `claude-code-install-manager.cmd help` renders correctly.
- [ ] `claude-code-install-manager.cmd doctor` renders correctly.
- [ ] If touching PATH handling: confirmed
      `[Environment]::GetEnvironmentVariable('Path','User')` before/after.
- [ ] If touching the spinner: tested with and without `CCT_NO_SPIN=1`.
- [ ] If touching `repair-system`: tested no-op path on a clean
      machine. (Don't fabricate a leftover by hand.)
- [ ] If touching `disable-desktop-alias`: tested with Desktop App
      installed.

## Documentation

- [ ] `CHANGELOG.md` has an `[Unreleased]` entry under the right
      section (Added / Changed / Fixed / Security / Deprecated /
      Removed).
- [ ] README updated if a user-visible behavior or flag changed.
- [ ] If adding a subcommand: appears in `help`, in the README
      **Subcommands** table, and follows the `:CmdXxx` naming
      convention.

## Linked issues

<!-- Closes #N, or Refs #N. -->

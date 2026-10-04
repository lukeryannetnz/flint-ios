# Proposal: Background file loading that keeps the app responsive

## Why

Flint currently performs some file work on the same thread that updates the screen. If Dropbox pauses while supplying a file, loading indicators and taps can stop working too. File loading needs its own limited background capacity and a clear way back to a usable screen.

## What Changes

- Move file permission checks, folder listing, reads/writes, image preparation and imports away from screen updates.
- Show slow progress after five seconds and a usable screen or recovery options within 30 active seconds.
- Limit background work and prevent work that finishes after cancellation from changing the current screen or document.

For example: A Dropbox read takes more than 30 seconds. Flint stops waiting and offers recovery. The read may still finish later, but it cannot reopen an old vault, replace the current note or trigger an obsolete alert. Its iOS permission remains valid until it actually finishes.

## Capabilities

### New Capabilities

- `provider-execution`: Describe how Flint does slow file work in the background, limits simultaneous work, and stops making the user wait indefinitely.

### Modified Capabilities

- `app-bootstrap`: How startup reopens the saved folder and handles failure.
- `vault-management`: Loading progress and cancellation.

## Impact

This follows PR #16, which supplies the preceding part of the plan. This PR contains proposed behavior and test requirements; it does not change the app yet. Implementation and real-iPhone testing remain separate tasks.

The [original combined plan](https://github.com/lukeryannetnz/flint-ios/pull/14) remains available for reference. The folder names are kept stable for OpenSpec; the document headings use plain English.

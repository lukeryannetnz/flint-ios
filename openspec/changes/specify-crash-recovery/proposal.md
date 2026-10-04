# Proposal: Crash reports, restart recovery and sharing debug logs

## Why

An iPhone can close Flint before it writes a final error message. On the next launch, opening the same Dropbox folder immediately can repeat the failure. Flint needs a safe restart path and a way to collect the information Apple makes available.

## What Changes

- Collect available crash and freeze reports without claiming that every unexpected exit is a crash.
- Remember when reopening a vault was interrupted, and offer recovery before retrying it.
- Let the user preview, share and clear saved debug information; do not upload it automatically.

For example: If Flint closes while reopening a Dropbox vault, the next launch should offer Retry, Choose another vault and Export diagnostics before touching that folder again. The message should say the previous attempt was interrupted, because force-quitting can look similar to a crash.

## Capabilities

### New Capabilities

- `crash-recovery`: Describe how Flint collects available crash and freeze information, avoids reopening the same failing vault automatically, and lets the user share debug logs.

### Modified Capabilities

- `app-bootstrap`: How startup reopens the saved folder and handles failure.

## Impact

This follows PR #15, which supplies the preceding part of the plan. This PR contains proposed behavior and test requirements; it does not change the app yet. Implementation and real-iPhone testing remain separate tasks.

The [original combined plan](https://github.com/lukeryannetnz/flint-ios/pull/14) remains available for reference. The folder names are kept stable for OpenSpec; the document headings use plain English.

# Proposal

## Why

Discovery currently reads every note to build previews, and introducing asynchronous saves creates revision/navigation races. Define incremental loading and data integrity as one document contract.

## What Changes

- Define the behavior in `note-loading` and its acceptance scenarios.
- Preserve this part of the original proposal while making it reviewable independently.

## Capabilities

### New Capabilities

- `note-loading`: Define incremental note discovery, lazy bounded previews, pending content states and revision-safe persistence for provider vaults.

### Modified Capabilities

- `note-management`: Auto-select an available note.

## Impact

Planning only; no app code or runtime configuration changes. Depends on the preceding spec PR; review this branch against its immediate predecessor.
Original reference: https://github.com/lukeryannetnz/flint-ios/pull/14 (preserved, superseded).
Review question: **How do notes stay usable without reading the entire vault or losing edits?**

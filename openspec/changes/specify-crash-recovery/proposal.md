# Proposal

## Why

Hard terminations may leave no final log, while reopening the same stalled vault can repeat the failure. Define independent evidence collection and recovery without claiming that an interrupted launch proves a crash.

## What Changes

- Define the behavior in `crash-recovery` and its acceptance scenarios.
- Preserve this part of the original proposal while making it reviewable independently.

## Capabilities

### New Capabilities

- `crash-recovery`: Define platform crash and hang evidence, interrupted-restoration recovery, and user-controlled local diagnostic export.

### Modified Capabilities

- `app-bootstrap`: Restore previously selected vault, Recover from stale or invalid bookmark data, Surface user-facing failures.

## Impact

Planning only; no app code or runtime configuration changes. Depends on the preceding spec PR; review this branch against its immediate predecessor.
Original reference: https://github.com/lukeryannetnz/flint-ios/pull/14 (preserved, superseded).
Review question: **What can we know after a crash or freeze, and how does the user recover?**

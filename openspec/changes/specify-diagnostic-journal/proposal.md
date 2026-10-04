# Proposal

## Why

Alerts do not show which Dropbox operation stalled, and evidence disappears after termination. Define content-free correlated events and bounded local storage before adding collection or recovery behavior.

## What Changes

- Define the behavior in `diagnostic-journal` and its acceptance scenarios.
- Preserve this part of the original proposal while making it reviewable independently.

## Capabilities

### New Capabilities

- `diagnostic-journal`: Define safe, correlated local diagnostic events and bounded storage for investigating provider-backed vault failures.

### Modified Capabilities

None.

## Impact

Planning only; no app code or runtime configuration changes. None; first PR in the replacement stack.
Original reference: https://github.com/lukeryannetnz/flint-ios/pull/14 (preserved, superseded).
Review question: **What evidence is useful, safe to retain, and cheap enough to collect?**

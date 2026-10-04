# Proposal

## Why

Main-actor synchronous coordination and enumeration can freeze the loading screen. Define background work, logical cancellation and resource lifetimes before migrating note and image callers.

## What Changes

- Define the behavior in `provider-execution` and its acceptance scenarios.
- Preserve this part of the original proposal while making it reviewable independently.

## Capabilities

### New Capabilities

- `provider-execution`: Define bounded background file execution, cancellation, access lifetimes and recoverable loading for Files-provider vaults.

### Modified Capabilities

- `app-bootstrap`: Initial launch state, Single active security-scoped vault.
- `vault-management`: Busy indication during vault operations.

## Impact

Planning only; no app code or runtime configuration changes. Depends on the preceding spec PR; review this branch against its immediate predecessor.
Original reference: https://github.com/lukeryannetnz/flint-ios/pull/14 (preserved, superseded).
Review question: **How do we keep the UI responsive when file coordination cannot be stopped?**

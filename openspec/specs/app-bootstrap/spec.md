# app-bootstrap Specification

## Purpose

Define how Flint launches, restores a previously selected vault, and decides whether to show onboarding or the main note browser.

Status: proposed revisions in this specification are not yet implemented; the associated change tasks track implementation and validation.

## Requirements

### Requirement: Initial launch state
The system SHALL start with a responsive branded loading screen while reopening the saved vault, show slow progress after 5 seconds, and show a usable browser or recovery options within 30 seconds while the app is on screen and active.

#### Scenario: Bootstrap starts
- GIVEN Flint has just launched
- WHEN its first screen appears
- THEN reopening the vault starts once, with a full-screen loading view until startup chooses the next screen
- AND the loading view covers the display, uses Flint branding and does not expose default system background chrome

#### Scenario: Provider restoration exceeds its deadline
- GIVEN provider content is unavailable or stuck
- WHEN the active loading time reaches its deadline
- THEN Flint offers Retry, Choose another vault and Export diagnostics
- AND those controls remain responsive without waiting for blocked work to stop

### Requirement: Onboarding without a stored vault

The system SHALL show onboarding when no vault bookmark has been stored.

#### Scenario: No stored bookmark

- GIVEN no persisted vault bookmark exists
- WHEN bootstrap runs
- THEN the app transitions to onboarding
- AND no active vault is selected

### Requirement: Restore previously selected vault
The system SHALL try to reopen the previously selected vault using its saved folder reference, except when an interrupted previous attempt requires recovery first. The saved reference is the bookmark data iOS uses to find that folder again.

#### Scenario: Stored bookmark resolves successfully
- GIVEN a vault reference has been saved
- WHEN startup finds that folder using the saved reference
- THEN Flint opens it in background work and shows the notes found so far
- AND the app reaches its ready state and keeps the saved vault choice

#### Scenario: Previous restoration was interrupted
- GIVEN the last attempt has no completion or handled cancellation/failure record
- WHEN Flint launches
- THEN recovery appears before trying to read the folder
- AND the saved folder reference remains available for explicit retry

### Requirement: Recover from stale or invalid bookmark data
The system SHALL clear a saved folder reference only when checking it proves it invalid or unusable. Temporary file-provider unavailability, cancellation or timeout SHALL keep the reference for retry.

#### Scenario: Stored bookmark cannot be resolved
- GIVEN a vault reference has been saved
- WHEN checking it establishes that the reference is invalid or unusable
- THEN Flint clears it, returns to setup and explains that the vault must be chosen again

#### Scenario: Bookmark resolution times out
- WHEN checking the reference times out or fails because the provider is temporarily unavailable
- THEN Flint offers recovery and logs the error category
- AND it does not clear the saved vault reference

### Requirement: Single active security-scoped vault
The system SHALL show one active vault while keeping iOS file permissions for any previous background operation that is still running. These permissions are security-scoped access: iOS grants the app temporary access to a chosen folder. Cancellation SHALL release permission only after the last operation using it finishes.

#### Scenario: Open a different vault
- GIVEN a vault is open
- WHEN the user chooses another vault
- THEN unsaved edits are saved or explicitly kept/discarded before editor state changes
- AND obsolete waiting autosaves are cancelled
- AND running operations keep permission for their original vault until they finish, without changing the newly selected vault’s screen or document
- AND access to the old vault is released when its remaining operations finish

### Requirement: Surface user-facing failures
The system SHALL show ordinary errors in dismissible alerts and loading errors on a recovery screen with Retry, Choose another vault and Export diagnostics.

#### Scenario: Vault opening fails
- GIVEN the user tries to open a vault
- WHEN opening fails
- THEN Flint shows recovery or setup as appropriate
- AND it clears failed new-vault state without discarding unresolved edits from the previous vault
- AND it shows an understandable error and recovery actions, and records the failed step and error category without private data

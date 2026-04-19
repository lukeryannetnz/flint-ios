# app-bootstrap Specification

## Purpose

Define how Flint launches, restores a previously selected vault, and decides whether to show onboarding or the main note browser.

## Requirements

### Requirement: Initial launch state

The system SHALL begin in a loading state while vault restoration is attempted.

#### Scenario: Bootstrap starts

- GIVEN the app has just launched
- WHEN the root view appears
- THEN the app model starts bootstrap once
- AND the interface shows a loading state until bootstrap decides the next phase

### Requirement: Onboarding without a stored vault

The system SHALL show onboarding when no vault bookmark has been stored.

#### Scenario: No stored bookmark

- GIVEN no persisted vault bookmark exists
- WHEN bootstrap runs
- THEN the app transitions to onboarding
- AND no active vault is selected

### Requirement: Restore previously selected vault

The system SHALL attempt to reopen the previously selected vault from persisted bookmark data.

#### Scenario: Stored bookmark resolves successfully

- GIVEN a persisted vault bookmark exists
- WHEN bootstrap resolves that bookmark
- THEN the app opens the resolved vault
- AND the app transitions to the ready state
- AND the vault selection remains persisted

### Requirement: Recover from stale or invalid bookmark data

The system SHALL discard an unusable stored bookmark and require the user to choose a vault again.

#### Scenario: Stored bookmark cannot be resolved

- GIVEN a persisted vault bookmark exists
- WHEN bookmark resolution fails
- THEN the stored bookmark is cleared
- AND the app transitions to onboarding
- AND the app shows an alert explaining that the previous vault must be selected again

### Requirement: Single active security-scoped vault

The system SHALL release security-scoped access for the previous vault before switching to another vault.

#### Scenario: Open a different vault

- GIVEN a vault is currently open
- WHEN the user opens another vault
- THEN any pending autosave task is cancelled
- AND security-scoped access to the previous vault is stopped before the new vault becomes active

### Requirement: Surface user-facing failures

The system SHALL present operational failures through a dismissible alert.

#### Scenario: Vault opening fails

- GIVEN the user attempts to open a vault
- WHEN the open operation fails
- THEN the app returns to onboarding
- AND active vault state, note selection, and editor contents are cleared
- AND the app shows the localized error message in an alert

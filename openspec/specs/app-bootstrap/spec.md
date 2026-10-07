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
- AND the interface shows a full-screen loading state until bootstrap decides the next phase
- AND the loading presentation covers the entire display without exposing default system background chrome
- AND the loading presentation uses Flint branding rather than a bare progress indicator

### Requirement: Onboarding without a stored vault

The system SHALL show onboarding when no vault bookmark has been stored.

#### Scenario: No stored bookmark

- GIVEN no persisted vault bookmark exists
- WHEN bootstrap runs
- THEN the app transitions to onboarding
- AND no active vault is selected

### Requirement: Restore previously selected vault

The system SHALL attempt to reopen the previously selected vault from persisted bookmark data only after restoration safety authorizes automatic access. An unfinished, corrupt, unreadable or unwritable safety marker SHALL show recovery before bookmark resolution or provider access. Explicit retry and choosing another vault SHALL preserve the bookmark unless resolution independently proves it unusable.

#### Scenario: Stored bookmark resolves successfully

- GIVEN a persisted vault bookmark exists
- WHEN bootstrap resolves that bookmark
- THEN the app opens the resolved vault
- AND the app transitions to the ready state
- AND the vault selection remains persisted

### Requirement: Recover from stale or invalid bookmark data

The system SHALL discard a stored bookmark only when resolution proves it invalid or unusable; temporary provider unavailability, cancellation, or timeout SHALL preserve it for retry.

#### Scenario: Stored bookmark cannot be resolved

- GIVEN a persisted vault bookmark exists
- WHEN bookmark resolution establishes that the bookmark is invalid or unusable
- THEN the stored bookmark is cleared
- AND the app transitions to onboarding
- AND the app shows an alert explaining that the previous vault must be selected again

### Requirement: Single active security-scoped vault

The system SHALL retain one UI-active vault scope and independent worker-owned scope leases. Switching releases the UI lease only after dirty text is saved; cancelled or timed-out workers retain their source and destination leases until actual completion.

#### Scenario: Open a different vault

- GIVEN a vault is currently open
- WHEN the user opens another vault
- THEN dirty text is saved before editor state changes, or navigation stays at the original destination
- AND any pending autosave task is cancelled
- AND the UI releases its previous scope while any draining worker retains its own balanced lease
- AND no obsolete operation can publish state into the new vault
- AND explicit retain/discard choices and document recovery remain planned for phase 4

### Requirement: Surface user-facing failures

The system SHALL present operational failures through a dismissible alert.

#### Scenario: Vault opening fails

- GIVEN the user attempts to open a vault
- WHEN the open operation fails
- THEN the app returns to onboarding
- AND active vault state, note selection, and editor contents are cleared
- AND the app shows the localized error message in an alert

### Requirement: Finish restoration safety records

Successful restoration SHALL commit completion; handled restoration failure SHALL commit abandonment. If that commit fails, the unfinished marker SHALL remain conservative on the next launch. Recovery SHALL describe interrupted restoration without asserting a crash. Diagnostic sharing remains part of the later export phase.

#### Scenario: Previous restoration was interrupted

- GIVEN an unfinished restoration marker exists
- WHEN bootstrap runs
- THEN recovery is shown without resolving or deleting the saved bookmark
- AND explicit retry can reopen the saved selection
- AND choosing another vault shows onboarding while preserving the bookmark

### Requirement: Bound asynchronous bootstrap setup

Bookmark resolution, creation and security-scope acquisition SHALL run on the bounded provider executor. Automatic restoration SHALL use one foreground-active attempt deadline, expose current stage and cancellation, and preserve bookmarks on temporary provider errors, cancellation and timeout. Only evidence of an invalid bookmark SHALL clear its saved data.

#### Scenario: User leaves a cancelled restoration

- WHEN the user chooses another vault while old work drains
- THEN a new vault uses the remaining worker slot when available
- AND old completion cannot replace new presentation or saved selection

#### Scenario: Choosing another vault overlaps safety storage

- WHEN choosing another vault awaits an app-local abandonment write and a newer vault opens meanwhile
- THEN completion of the old safety write cannot replace the newer vault screen with onboarding

#### Scenario: Valid bookmark resolves before content corruption

- WHEN bookmark resolution succeeds but discovery or note reading reports corrupt content
- THEN the saved bookmark remains available for retry
- AND corruption in a later file stage is not evidence of invalid bookmark data

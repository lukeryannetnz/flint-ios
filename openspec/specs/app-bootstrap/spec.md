# app-bootstrap Specification

## Purpose

Users need to return to their notes after launching Flint. Reopening a saved vault can fail or stall, especially when its files come from a service such as Dropbox. Flint must keep the screen usable and offer recovery without losing the saved vault selection.

This spec defines startup, restoration of the previous vault, and the choice between onboarding and the note browser. A bookmark is saved iOS permission data used to reopen a chosen folder. A security-scoped access lease keeps that permission active while the interface or a file worker needs it.

## Requirements

### Requirement: Initial launch state

The system SHALL begin in a loading state while vault restoration is attempted.

#### Scenario: Bootstrap starts

- GIVEN the app has just launched
- WHEN the root view appears
- THEN the app model starts bootstrap once
- AND the interface shows a full-screen loading screen until bootstrap decides the next phase
- AND the loading presentation covers the entire display without exposing default system background or controls
- AND the loading presentation uses Flint branding rather than a bare progress indicator

### Requirement: Onboarding without a stored vault

The system SHALL show onboarding when no vault bookmark has been stored.

#### Scenario: No stored bookmark

- GIVEN no persisted vault bookmark exists
- WHEN bootstrap runs
- THEN the app transitions to onboarding
- AND no active vault is selected

### Requirement: Restore previously selected vault

Before reopening the saved vault, Flint SHALL check its restoration safety marker. This local record tracks whether a previous restoration finished.

Flint SHALL show recovery before resolving the bookmark or accessing the provider if the marker is unfinished, corrupt, unreadable, or unwritable. Explicit retry and choosing another vault SHALL preserve the bookmark unless bookmark resolution separately proves it unusable.

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

Flint SHALL keep one access lease for the vault shown in the interface. File workers SHALL hold their own leases.

When switching vaults, Flint SHALL release the interface lease only after saving unsaved text. Cancelled or timed-out workers SHALL keep their source and destination leases until they actually finish.

#### Scenario: Open a different vault

- GIVEN a vault is currently open
- WHEN the user opens another vault
- THEN unsaved text is saved before editor state changes, or navigation stays at the original destination
- AND any pending autosave task is cancelled
- AND the UI releases its previous scope while any worker that is still finishing retains its own balanced lease
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

After successful restoration, Flint SHALL save a completed marker. After a handled restoration failure, it SHALL save an abandoned marker. If either write fails, the unfinished marker SHALL still require recovery on the next launch.

Recovery SHALL describe interrupted restoration without claiming that a crash occurred. Diagnostic sharing remains part of the later export phase.

#### Scenario: Previous restoration was interrupted

- GIVEN an unfinished restoration marker exists
- WHEN bootstrap runs
- THEN recovery is shown without resolving or deleting the saved bookmark
- AND explicit retry can reopen the saved selection
- AND choosing another vault shows onboarding while preserving the bookmark

### Requirement: Bound asynchronous bootstrap setup

Resolving and creating bookmarks, and acquiring iOS file permission, SHALL run on the provider executor. This scheduler limits the number of file workers.

Automatic restoration SHALL use one deadline that counts only foreground-active time. It SHALL show the current stage and allow cancellation. Temporary provider errors, cancellation, and timeout SHALL preserve bookmarks. Flint SHALL clear saved bookmark data only when evidence shows that the bookmark is invalid.

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

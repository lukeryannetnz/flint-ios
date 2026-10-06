## MODIFIED Requirements

### Requirement: Initial launch state

The system SHALL begin in a responsive branded loading state while vault restoration is attempted, expose slow progress after 5 seconds, and reach a usable browser or recoverable failure within 30 seconds of foreground-active time.

#### Scenario: Bootstrap starts

- GIVEN the app has just launched
- WHEN the root view appears
- THEN the app model starts bootstrap once
- AND the interface shows a full-screen loading state until bootstrap decides the next phase
- AND the loading presentation covers the entire display without exposing default system background chrome
- AND the loading presentation uses Flint branding rather than a bare progress indicator

#### Scenario: Provider restoration exceeds its deadline

- GIVEN provider content is unavailable or stalled
- WHEN restoration reaches its foreground loading deadline
- THEN the loading presentation offers Retry, Choose another vault, and Export diagnostics
- AND it remains interactive without waiting for blocked work to stop


### Requirement: Restore previously selected vault

The system SHALL attempt to reopen the previously selected vault from persisted bookmark data unless an unfinished previous restoration requires recovery first.

#### Scenario: Stored bookmark resolves successfully

- GIVEN a persisted vault bookmark exists
- WHEN bootstrap resolves that bookmark
- THEN the app opens the resolved vault asynchronously and publishes usable discovery results
- AND the app transitions to the ready state
- AND the vault selection remains persisted

#### Scenario: Previous restoration was interrupted

- GIVEN the previous restoration marker has no completion or handled-abandonment record
- WHEN Flint launches
- THEN recovery is shown before provider access
- AND the saved bookmark remains available for explicit retry


### Requirement: Recover from stale or invalid bookmark data

The system SHALL discard a stored bookmark only when resolution proves it invalid or unusable; temporary provider unavailability, cancellation, or timeout SHALL preserve it for retry.

#### Scenario: Stored bookmark cannot be resolved

- GIVEN a persisted vault bookmark exists
- WHEN bookmark resolution establishes that the bookmark is invalid or unusable
- THEN the stored bookmark is cleared
- AND the app transitions to onboarding
- AND the app shows an alert explaining that the previous vault must be selected again

#### Scenario: Bookmark resolution times out

- WHEN resolution times out or fails because the provider is temporarily unavailable
- THEN Flint presents recovery and records the error category
- AND it does not clear the saved bookmark


### Requirement: Single active security-scoped vault

The system SHALL maintain one UI-active vault while retaining security-scoped access leases for any previous worker that has not actually stopped. Cancellation SHALL release an access lease only after the last operation using it finishes.

#### Scenario: Open a different vault

- GIVEN a vault is currently open
- WHEN the user opens another vault
- THEN unsaved edits are persisted or explicitly retained/discarded before editor state changes
- AND any queued obsolete autosave task is cancelled
- AND operations already running retain access to their original vault until completion
- AND no obsolete operation can publish state into the new vault
- AND access to the previous vault is stopped once its remaining workers finish

### Requirement: Surface user-facing failures

The system SHALL present ordinary operational failures through a dismissible alert and loading failures through a recoverable screen with Retry, Choose another vault, and Export diagnostics.

#### Scenario: Vault opening fails

- GIVEN the user attempts to open a vault
- WHEN the open operation fails
- THEN the app shows loading recovery or onboarding as appropriate
- AND failed new-vault state is cleared without discarding unresolved edits from a previous vault
- AND the app shows a user-facing error message and recovery actions
- AND sanitized diagnostics retain the failed stage and error category

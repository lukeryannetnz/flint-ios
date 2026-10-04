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

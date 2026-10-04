## MODIFIED Requirements

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

### Requirement: Surface user-facing failures

The system SHALL present ordinary operational failures through a dismissible alert and loading failures through a recoverable screen with Retry, Choose another vault, and Export diagnostics.

#### Scenario: Vault opening fails

- GIVEN the user attempts to open a vault
- WHEN the open operation fails
- THEN the app shows loading recovery or onboarding as appropriate
- AND failed new-vault state is cleared without discarding unresolved edits from a previous vault
- AND the app shows a user-facing error message and recovery actions
- AND sanitized diagnostics retain the failed stage and error category

## MODIFIED Requirements

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

### Requirement: Single active security-scoped vault
The system SHALL show one active vault while keeping iOS file permissions for any previous background operation that is still running. These permissions are security-scoped access: iOS grants the app temporary access to a chosen folder. Cancellation SHALL release permission only after the last operation using it finishes.

#### Scenario: Open a different vault
- GIVEN a vault is open
- WHEN the user chooses another vault
- THEN unsaved edits are saved or explicitly kept/discarded before editor state changes
- AND obsolete waiting autosaves are cancelled
- AND running operations keep permission for their original vault until they finish, without changing the newly selected vault’s screen or document
- AND access to the old vault is released when its remaining operations finish

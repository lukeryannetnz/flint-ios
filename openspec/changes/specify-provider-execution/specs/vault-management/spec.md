## MODIFIED Requirements

### Requirement: Busy indication during vault operations
The system SHALL show responsive progress while creating or opening a vault, including the current step and files found, with cancellation and recovery for slow providers.

#### Scenario: Long-running vault operation
- GIVEN a vault is being created or opened
- WHEN the operation is running
- THEN Flint shows that it is busy, along with progress and cancellation
- AND recovery controls remain usable
- AND it does not show a made-up download percentage

#### Scenario: Cancel a provider-backed vault operation
- WHEN the user cancels creating or opening a vault
- THEN Flint asks the background work to stop and promptly ends the waiting screen
- AND it explains any still-unknown creation result before a safe retry
- AND work that finishes later cannot replace the current app state

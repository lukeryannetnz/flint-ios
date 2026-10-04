## MODIFIED Requirements

### Requirement: Busy indication during vault operations

The system SHALL show responsive busy state and stage/count progress while vault creation or opening is in progress, with cancellation and bounded recovery for provider delays.

#### Scenario: Long-running vault operation

- GIVEN the user is creating or opening a vault
- WHEN the operation is running
- THEN the app exposes busy state
- AND the current screen presents progress and cancellation without disabling recovery controls
- AND the app does not present an invented download percentage

#### Scenario: Cancel a provider-backed vault operation

- WHEN the user cancels vault creation or opening
- THEN the app requests worker cancellation and exits its blocking presentation
- AND it reports any uncertain creation outcome before offering a safe retry
- AND late work cannot replace current app state

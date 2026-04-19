# vault-management Specification

## Purpose

Define how Flint lets users create a new vault or open an existing vault folder from Files providers while preserving future access with bookmarks.

## Requirements

### Requirement: Create vault from onboarding

The system SHALL let the user create a vault by naming it and choosing a parent folder.

#### Scenario: Create a new vault

- GIVEN the user is on onboarding
- AND the user has entered a non-empty vault name
- WHEN the user chooses a parent folder in Files
- THEN Flint creates a new directory with that vault name inside the selected parent folder
- AND Flint opens the created vault
- AND Flint persists bookmark data for reopening that vault later

### Requirement: Open existing vault from Files

The system SHALL let the user select an existing vault folder from Files providers.

#### Scenario: Open vault from picker

- GIVEN the user chooses to open a vault
- WHEN the user selects a folder in the folder picker
- THEN Flint opens that folder as the active vault
- AND Flint persists bookmark data for reopening that vault later

### Requirement: Support external file providers

The system SHALL use the iOS Files picker for vault selection so provider-backed folders can be used.

#### Scenario: Provider-backed folder

- GIVEN the user stores notes in a Files provider such as Dropbox
- WHEN the user selects a folder from that provider
- THEN Flint treats that folder as a vault
- AND file operations continue through coordinated file access

### Requirement: Validate vault names

The system SHALL reject invalid vault names before creating a new vault directory.

#### Scenario: Empty vault name

- GIVEN the user attempts to create a vault
- WHEN the provided name is empty or whitespace only
- THEN the system rejects the name
- AND the user receives a "Please provide a name." error

#### Scenario: Unsupported characters in vault name

- GIVEN the user attempts to create a vault
- WHEN the provided name contains `/` or `:`
- THEN the system rejects the name
- AND the user receives an unsupported characters error that includes the rejected name

### Requirement: Prevent duplicate vault creation

The system SHALL not overwrite an existing directory when creating a vault.

#### Scenario: Vault directory already exists

- GIVEN the selected parent folder already contains a directory with the requested vault name
- WHEN Flint attempts to create the vault
- THEN the operation fails
- AND the user receives an already exists error for that name

### Requirement: Busy indication during vault operations

The system SHALL show busy state while vault creation or vault opening is in progress.

#### Scenario: Long-running vault operation

- GIVEN the user is creating or opening a vault
- WHEN the operation is running
- THEN the app exposes busy state
- AND the current screen presents a progress indicator overlay

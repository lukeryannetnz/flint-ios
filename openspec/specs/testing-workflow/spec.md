# Testing Workflow

## Purpose

Define how Flint's automated test suite should run for contributors and CI, including the default simulator lane and the optional device-validation lane.

### Requirement: Simulator test lane is the default

The system SHALL support running the full Flint automated test suite on an iOS Simulator without requiring developer-specific code signing configuration.

#### Scenario: Contributor runs the required test suite

- GIVEN a contributor has Xcode installed
- WHEN they run the default Flint test command
- THEN the tests target an iOS Simulator destination
- AND the run does not require a developer team, provisioning profile, or connected physical device

### Requirement: Device validation remains available when needed

The system SHALL continue to support running the Flint test suite on a connected physical device for additional validation when local signing is configured.

#### Scenario: Contributor runs device validation

- GIVEN a contributor has configured local signing overrides
- AND a physical iOS device destination is available
- WHEN they run the device validation command
- THEN the tests build and run for that device destination
- AND the workflow does not require committing developer-specific team identifiers to the repository

### Requirement: Local signing remains developer-specific

The system SHALL keep device-signing configuration outside version control.

#### Scenario: Contributor configures local signing

- GIVEN the repository is checked out on a contributor machine
- WHEN the contributor needs to run device validation
- THEN they can provide a local, untracked signing configuration
- AND the checked-in project configuration does not hard-code a specific developer team for all contributors

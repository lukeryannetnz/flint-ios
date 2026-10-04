# Testing Workflow

## Purpose

Define how Flint's automated test suite should run for contributors and CI, including the default simulator lane and the optional device-validation lane.

## Requirements

### Requirement: GitHub Actions builds and tests pull requests

The repository SHALL provide a GitHub Actions workflow that builds Flint for an iOS Simulator and runs the full shared Flint scheme, including unit and UI tests, on pushes to `main`, pull requests targeting `main`, and manual dispatches.

#### Scenario: CI validates a change

- WHEN the workflow is triggered
- THEN a macOS runner selects a stable Xcode installation and an available iPhone simulator from the newest installed iOS runtime
- AND simulator startup completes before building and testing
- AND the workflow builds for testing and runs tests without rebuilding or requiring signing credentials
- AND build, simulator startup, and test failures fail the job without automatic test retries
- AND superseded runs are cancelled and the job has a bounded timeout

#### Scenario: Test results are available for investigation

- WHEN the test step produces an Xcode result bundle, whether tests pass or fail
- THEN the workflow uploads the result bundle as a downloadable artifact retained for 14 days

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


### Requirement: Note image workflows have automated UI or integration coverage
The system SHALL include deterministic automated coverage for user-facing note image workflows in the default simulator test lane.

#### Scenario: Existing inline image renders in the note surface
- **GIVEN** a test vault contains a markdown note with a valid local image reference
- **WHEN** the automated test opens that vault and selects the note
- **THEN** Flint renders the image in the note surface
- **AND** the automated test verifies successful image loading and visible image bounds rather than relying solely on an accessibility identifier
- **AND** Flint shows any markdown alt text as caption content when present

#### Scenario: Fullscreen image viewer opens and dismisses
- **GIVEN** a note surface displays an inline image
- **WHEN** the automated test activates that image
- **THEN** Flint presents the fullscreen image viewer
- **AND** the automated test can dismiss the viewer and return to the unchanged note
- **AND** the automated test verifies the saved note markdown is identical before opening and after dismissing the viewer
- **AND** the editor content remains unchanged with no pending unsaved changes after dismissal

#### Scenario: Missing image reference remains readable
- **GIVEN** a test vault contains a markdown note with an image reference that cannot be loaded
- **WHEN** the automated test opens the note
- **THEN** Flint shows a broken-image state without crashing
- **AND** the rest of the note remains readable

#### Scenario: Inserted image persists as a portable vault asset
- **GIVEN** a test vault has an editable markdown note
- **WHEN** the automated test inserts an image at a known cursor position from a deterministic test source and saves the note
- **THEN** Flint copies the image into the note-adjacent managed asset folder
- **AND** the saved note contains a standard relative markdown image reference at the selected insertion position rather than an absolute device-specific path
- **AND** the text before and after that insertion remains intact and in its original order
- **AND** the test removes the original import source when a source file exists
- **AND** the stored reference resolves inside the note's managed asset folder within the vault
- **AND** terminating and relaunching Flint with the same saved fixture vault, without reseeding it, renders the inserted image from the stored markdown reference

#### Scenario: Each insertion source exercises Flint's authoring flow
- **GIVEN** separate automated cases provide deterministic image selections for Files, the photo library, and the camera
- **WHEN** each case selects its source and supplies its image through a substitute for the system picker or capture result
- **THEN** Flint's corresponding source callback imports the image and inserts it through the real editor flow
- **AND** each case verifies cursor placement, preservation of surrounding text, managed asset storage, a saved relative markdown reference, and rendering after reopening the note

#### Scenario: Failed image insertion save can be retried
- **GIVEN** an image has been inserted into an editable note
- **WHEN** a deterministic test failure prevents saving the note
- **THEN** Flint reports the save error and retains the unsaved edit and referenced managed asset for retry
- **AND** after the failure is removed, retrying the save persists the relative reference and its referenced managed asset
- **AND** the debug-only failure fixture provides an explicit retry action in the save-error alert so keyboard focus and repeated save alerts cannot intercept a tap on an underlying control
- **AND** the test verifies the retained draft and managed asset before invoking that alert action and verifies persistence after relaunch

#### Scenario: Default simulator lane runs image workflow coverage
- **GIVEN** a contributor runs the required simulator test command
- **WHEN** the Flint test suite executes
- **THEN** the note image UI or integration workflow coverage runs without requiring manual picker interaction, photo-library state, camera hardware, or external Files provider setup

### Requirement: Test failures remain failures until explained and resolved
The validation workflow SHALL treat an unexplained test failure as a failure even when a subsequent retry passes.

#### Scenario: A failing test passes on retry
- **WHEN** a required test run fails and a subsequent retry passes
- **THEN** the initial failure remains part of the validation result
- **AND** the change is not declared validated solely on the basis of the passing retry

### Requirement: Source adapter and permission changes require device validation
Changes to production image source-adapter behavior or permissions SHALL receive a recorded physical-device smoke test before completion. Debug-only substitutes and unchanged callback extraction do not alone trigger this requirement. Other changes retain optional device validation.

#### Scenario: Image source behavior or permissions change
- **WHEN** a change modifies production image source-adapter behavior or permissions
- **THEN** actual affected Files, photo-library, or camera workflows are smoke-tested on a physical device
- **AND** the tested commit, device/iOS version, affected sources, and selection/capture, insertion, save/reopen, cancellation, and applicable permission-denial outcomes are recorded before completion

#### Scenario: A required device is unavailable
- **GIVEN** a change requires physical-device validation
- **WHEN** no suitable device is available
- **THEN** simulator validation may finish
- **AND** the change remains awaiting device validation and is not declared complete

### Requirement: Folder-aware note creation has automated coverage
The default simulator lane SHALL verify that creating a note uses the destination displayed in the creation sheet, including a nested folder and Recent mode after browsing that folder. Coverage SHALL also verify nested note selection completes without delayed fallback navigation, duplicate names within a destination are rejected, and matching filenames in different folders are allowed.

#### Scenario: Create notes through the folder browser and Recent mode
- **GIVEN** a deterministic test vault contains a nested folder
- **WHEN** the automated test browses that folder and creates a note
- **THEN** the sheet displays that folder and the created note is stored there
- **AND** after switching to Recent mode, the sheet displays Vault Root and creation stores the note at the root

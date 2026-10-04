# Testing Workflow

## Purpose

Define how Flint's automated test suite should run for contributors and CI, including the default simulator lane and the optional device-validation lane.

Status: proposed revisions in this specification are not yet implemented; the associated change tasks track implementation and validation.

## Requirements

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
Changes to production image source-adapter behavior or permissions SHALL receive a recorded physical-device smoke test before completion. Debug-only substitutes and unchanged callback extraction do not alone trigger this requirement. Changes to provider diagnostics or background vault, note or image access also require the recorded physical-iPhone Dropbox acceptance defined below. Changes outside these categories retain optional device validation.

#### Scenario: Image source behavior or permissions change
- **WHEN** a change modifies production image source-adapter behavior or permissions
- **THEN** actual affected Files, photo-library, or camera workflows are smoke-tested on a physical device
- **AND** the tested commit, device/iOS version, affected sources, and selection/capture, insertion, save/reopen, cancellation, and applicable permission-denial outcomes are recorded before completion

#### Scenario: A required device is unavailable
- **GIVEN** a change requires physical-device validation
- **WHEN** no suitable device is available
- **THEN** simulator validation may finish
- **AND** the change remains awaiting device validation and is not declared complete


### Requirement: Provider diagnostics and asynchronous access require physical-device validation
Changes to debug logging or background vault, note or image access SHALL include repeatable simulator failure tests and recorded Dropbox tests on a physical iPhone before being declared validated. Simulator success alone SHALL not establish that the real provider is responsive or crash recovery works.

#### Scenario: Dropbox device acceptance
- GIVEN a vault containing downloaded, pending and unavailable notes/images
- WHEN launching, switching notes, saving, importing, scrolling and closing image viewers online, offline and during download
- THEN the record includes the tested code version, device/iOS version, provider version when available, test-file sizes/state, timings, outcomes and checks that files/edits are intact
- AND an Instruments performance recording verifies provider waits and image decoding are absent from the screen-update thread
- AND debug-log export, interrupted-launch recovery, cancellation, timeout and ignoring obsolete results are checked
- AND available crash reports, reports of iOS closing a frozen app, memory-limit termination reports and platform diagnostics are kept with matching debugging symbols, or their absence is recorded explicitly

#### Scenario: Physical device is unavailable
- WHEN simulator tests pass but a suitable iPhone/Dropbox setup is unavailable
- THEN device validation stays pending
- AND the result does not claim the reported iPhone failure is fixed

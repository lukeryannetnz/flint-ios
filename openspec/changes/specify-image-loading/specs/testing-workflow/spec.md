## MODIFIED Requirements

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

## ADDED Requirements

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

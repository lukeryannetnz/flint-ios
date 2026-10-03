## ADDED Requirements

### Requirement: Provider diagnostics and asynchronous access require physical-device validation

Changes to provider diagnostics and asynchronous vault, note, or image access SHALL include deterministic simulator fault coverage and a recorded physical-iPhone Dropbox validation before being declared validated. Simulator success alone SHALL NOT establish provider responsiveness or crash recovery.

#### Scenario: Dropbox device acceptance

- GIVEN a vault with fully downloaded, pending, and unavailable notes and images
- WHEN launch, note switching, saving, importing, scrolling, and viewer dismissal are exercised online, offline, and during download
- THEN the validation records the commit, device/iOS version, provider version when available, fixture size/state, timings, outcomes, and data-integrity checks
- AND an Instruments trace verifies provider waits and image decoding are absent from the main thread
- AND diagnostic export, interrupted-launch recovery, cancellation, timeout, and late-result rejection are verified
- AND available crash, watchdog, jetsam, and platform diagnostic evidence is retained with symbol files or explicitly recorded as unavailable

#### Scenario: Physical device is unavailable

- WHEN deterministic simulator validation passes but no suitable iPhone/Dropbox setup is available
- THEN the change remains awaiting device validation
- AND the result does not claim the reported physical-device failure is resolved

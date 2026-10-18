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

### Requirement: Observe actual worker completion in fault tests

Blocked-worker fault tests SHALL distinguish logical deadline completion from actual worker return using explicit lifecycle notifications. Cleanup assertions SHALL follow notification that slots and leases were released, rather than a short wall-clock polling assumption. Controlled foreground deadlines SHALL remain unchanged. Hosted CI SHALL run simulator test runners serially to avoid unnecessary cloned simulator resource contention while still exercising concurrency inside the bounded executor.

#### Scenario: Worker cleanup is delayed on the CI host

- WHEN a deliberately blocked accessor returns after logical timeout
- THEN the test awaits actual slot release with a bounded test-harness wait
- AND it verifies capacity and scope balance after completion
- AND scheduler delays do not change the tested foreground deadline

### Requirement: Exercise bounded note loading through the browser

The simulator UI suite SHALL exercise oversized selected content through the real file adapter and verify that the browser remains usable without an editable placeholder. Fault fixtures SHALL be confined to a UUID-scoped app-local test directory and excluded from Release behavior.

#### Scenario: Oversized initial note

- WHEN a fixture exceeds the 8 MiB read limit
- THEN the app presents the size-limit error without an editable partial document
- AND the user can dismiss the error and select another note successfully

# provider-execution Specification

## Purpose

Define bounded background file execution, cancellation, access lifetimes and recoverable loading for Files-provider vaults.

Status: planned; the associated change's unchecked tasks identify implementation and validation still required.

## Requirements

### Requirement: Isolate blocking provider work
The system SHALL perform bookmark resolution/creation, security-scope acquisition, coordination, enumeration, metadata lookup, file creation/read/write/copy, image import/encoding and decoding outside the main actor. Presentation updates SHALL remain on the main actor; a main-actor Task wrapping synchronous calls SHALL NOT satisfy isolation.

#### Scenario: Provider pauses during vault opening
- WHEN a Files provider delays access to partially downloaded files
- THEN rendering, taps, progress, cancellation and diagnostic export remain interactive
- AND coordinated file access and original source/destination access scopes remain in use
- AND evidence distinguishes coordination wait from accessor work

### Requirement: Bound attempts and worker capacity
The system SHALL expose a slow state after five seconds and a usable screen or recoverable failure by 30 seconds of foreground-active loading. Foreground note/image reads and imports SHALL use the same deadline. Work SHALL be limited to two active blocking jobs, one per vault, and 32 pending jobs; UI deadlines SHALL pause during background suspension.

#### Scenario: Timeout occurs inside an accessor
- WHEN a loading attempt times out or is cancelled
- THEN the UI recovers without awaiting a blocked accessor, requests cancellation and invalidates the attempt ID
- AND late results cannot modify current vault, editor, selection or alert state
- AND cancelled queued jobs are removed; retries do not create unlimited replacement workers
- AND another vault may use the remaining slot, while retrying the draining vault reports that work is still stopping
- AND if both slots remain blocked, new work returns a recoverable busy state
- AND access scopes are released only after actual worker completion

### Requirement: Expose honest progress and outcomes
The system SHALL show operation stage and observed discovery counts, not invented totals or download percentages. Timed-out writes/creation SHALL report uncertain outcomes rather than claiming rollback. Loading recovery SHALL offer Retry, Choose another vault and Export diagnostics and preserve bookmarks unless independently proven invalid.

#### Scenario: Cancel a vault attempt
- WHEN the user cancels creation or opening
- THEN the loading presentation ends promptly and evidence records cancellation
- AND an already-running accessor may finish without changing current UI state
- AND retry of a write or creation waits for its outcome rather than overlapping it

### Requirement: Verify real provider responsiveness
The implementation SHALL include deterministic blocked-before-accessor and blocked-inside-accessor tests and recorded physical-iPhone Dropbox validation before being declared validated.

#### Scenario: Provider acceptance
- WHEN downloaded, partially downloaded and unavailable fixtures are exercised online, offline and during download
- THEN a trace verifies no provider wait is on the main thread, deadlines hold, capacity/access lifetimes are bounded and files remain intact
- AND commit, device/iOS/provider versions, fixture state, timings and available crash/watchdog/jetsam reports are recorded
- AND missing device evidence leaves validation pending even if simulator tests pass

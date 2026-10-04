# Background file loading that keeps the app responsive

## Purpose

Describe how Flint does slow file work in the background, limits simultaneous work, and stops making the user wait indefinitely.

Status: proposed behavior, not yet implemented. The task list records the work and testing still needed.

## ADDED Requirements

### Requirement: Do slow file work away from screen updates
The system SHALL perform saved-folder-reference lookup/creation, iOS file-permission setup, read/write coordination, folder listing, file-detail lookup, file creation/read/write/copy, image imports/encoding and image preparation outside the main actor, the thread responsible for screen updates. Starting a Task on that same thread SHALL not count as background work.

#### Scenario: Dropbox pauses while supplying a file
- WHEN a file provider, such as Dropbox through the Files app, delays partially downloaded content
- THEN the screen, taps, progress, cancellation and debug-log export remain responsive
- AND Flint still coordinates reads/writes with iOS and keeps permission for the original source/destination
- AND logs distinguish waiting for iOS/provider access from the actual file read or write

### Requirement: Limit waiting time and simultaneous background work
The system SHALL show a slow state after five seconds and a usable screen or recovery options within 30 seconds while the app is on screen and active. Note/image reads and imports SHALL use the same deadline. At most two blocking jobs SHALL run at once, at most one per vault, with at most 32 waiting; time suspended in the background SHALL not count toward these deadlines.

#### Scenario: A started read does not stop when cancelled
- WHEN a loading attempt times out or the user cancels it
- THEN Flint stops making the screen wait, asks the file operation to stop, and marks that attempt as obsolete
- AND later results cannot change the current vault, editor text, note selection or alert
- AND cancelled waiting jobs are removed; retry does not start unlimited replacement jobs
- AND another vault can use the remaining job slot, while retrying the still-running vault explains that its previous work has not stopped yet
- AND if both slots are still blocked, new requests get a recoverable busy message
- AND iOS file permissions are released only when the corresponding work actually finishes

### Requirement: Show progress and write outcomes honestly
The system SHALL show the current step and the number of files found rather than inventing a total or download percentage. A timed-out save or creation SHALL have an unknown outcome until its work finishes, not be described as rolled back. Recovery SHALL offer Retry, Choose another vault and Export diagnostics, preserving saved vault references unless independently proven invalid.

#### Scenario: Cancel opening or creating a vault
- WHEN the user cancels the attempt
- THEN the waiting screen ends promptly and the cancellation is logged
- AND already-started file work may finish without changing the current screen
- AND another save/creation attempt waits for the first result instead of overlapping it

### Requirement: Test the behavior with real Dropbox files on an iPhone
The implementation SHALL include repeatable tests for blocked access before and during a read/write, plus recorded physical-iPhone Dropbox tests before it is declared validated.

#### Scenario: Check downloaded and partly downloaded files
- WHEN downloaded, partially downloaded and unavailable test files are opened online, offline and during download
- THEN a performance recording shows no file-provider waiting on the screen-update thread, deadlines are met, work/permission limits hold and files are intact
- AND the tested code version, device/iOS/Dropbox versions, test-file state, timings and available crash/OS-termination reports are recorded
- AND successful simulator tests do not replace missing iPhone evidence

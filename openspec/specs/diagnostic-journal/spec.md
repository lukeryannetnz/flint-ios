# Debug logs that help explain failures

## Purpose

When file loading fails, developers need to know what Flint was doing and where it stopped. The debug log must provide that evidence without exposing private notes or slowing down editing.

This spec defines the debug log saved on the iPhone, its privacy rules, and its storage limits.

Status: implemented and simulator-tested. Real-iPhone Dropbox performance validation remains pending. Logging alone does not establish that provider hangs or crashes are fixed.

## Requirements

### Requirement: Record what the app is doing and how long it takes
Flint SHALL start debug logging in development and release builds before trying to reopen a vault. It SHALL record each action from its start through its final result.

Each entry SHALL include the log format version, date and time, elapsed time measured independently of the wall clock, severity, step, result, app version and build, launch ID, and action ID. It SHALL include the parent action ID where needed to connect related actions.

#### Scenario: Follow a file-loading or saving action
- WHEN Flint opens or edits a vault stored through the Files app
- THEN the log covers saved-folder access, iOS file permission, waiting for permission to read/write, the actual read/write, listing files, file details, previews, note reads/saves, text formatting, image reads/preparation/imports and the first usable screen
- AND it records durations, file counts, bytes read, memory warnings and save results when known
- AND each action has one final result: success, failure, cancellation, timeout or abandonment
- AND work that finishes after a timeout gets a separate “finished later” entry rather than changing the original result
- AND timing markers let a developer match these actions to an iPhone performance recording

### Requirement: Keep private document information out of logs
Flint SHALL save and export only explicitly permitted fields. Error categories and codes SHALL come from limited lists. File identifiers SHALL change on each app launch.

Logs SHALL exclude note text, file and folder paths, titles, captions, image contents, saved folder-permission data, account details, and credentials. They SHALL also exclude unrestricted error descriptions and error dictionaries.

#### Scenario: A preview cannot be read
- WHEN Flint cannot read a preview or file details and uses a placeholder
- THEN the log distinguishes that failure from successfully reading an empty file and records the step and safe error codes
- AND it distinguishes missing files, unavailable downloads, permission failures, read/write coordination problems, invalid saved-folder references and unreadable images only when the evidence supports that conclusion
- AND classification uses the failed step and explicit platform error evidence; a corrupt bookmark, failed coordination, and failed image decoding have distinct categories
- AND explicit provider-unavailable and download-unavailable errors have distinct categories; an unrecognized error stays unknown
- AND unknown download/provider state stays unknown; a path or iCloud-only status does not prove a Dropbox file is downloaded

### Requirement: Limit log storage and its effect on performance
The system SHALL save versioned debug logs in protected app storage on the iPhone, outside the vault. It SHALL retain at most 20 MiB of logs for at most seven days, removing the oldest first. Logging SHALL not read Dropbox files, write to disk on the thread that updates the screen, or block note editing when logging fails.

#### Scenario: Log storage is slow, full or damaged
- WHEN log writing falls behind or storage fails
- THEN at most 512 entries wait to be written, each normal entry is at most 16 KiB, and each log-file segment is at most 256 KiB
- AND excess or oversized entries are skipped, with a limited counter recording the loss, instead of making the app wait
- AND accumulated loss counts remain pending until their counter entry is successfully saved, including across repeated storage failures
- AND an incomplete entry does not prevent startup, and old/expired entries are removed first
- AND a logging error does not trigger an endless stream of new log errors or crash the app

### Requirement: Share a safe logging interface with recovery features
The logger SHALL provide typed action and step identifiers. Typed identifiers use declared code types so the compiler can check which values callers supply, rather than accepting arbitrary strings.

The logger SHALL also provide error categories filtered for privacy and asynchronous snapshots of complete saved entries. A snapshot is a copy of the saved log entries available at the time of the request.

Snapshot reads SHALL use only app-local storage and skip invalid or incomplete records. No logging interface SHALL accept arbitrary messages or document text.

#### Scenario: A recovery feature needs logs while a provider is stuck
- WHEN it asks the logger for saved entries
- THEN the request runs on the log writer rather than a provider worker or screen-update thread
- AND the result contains only valid versioned entries within the retention limits

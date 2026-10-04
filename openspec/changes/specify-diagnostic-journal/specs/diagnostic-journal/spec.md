# diagnostic-journal Specification

## Purpose

Define safe, correlated local diagnostic events and bounded storage for investigating provider-backed vault failures.

Status: planned; the associated change's unchecked tasks identify implementation and validation still required.

## ADDED Requirements

### Requirement: Record correlated operation evidence
The system SHALL record events in Debug and Release before restoration starts, with schema version, UTC time, monotonic elapsed time, severity, stage, outcome, build/version, launch ID, operation ID, and parent ID when applicable. Outcomes SHALL distinguish success, failure, cancellation, timeout, and abandonment.

#### Scenario: Trace provider work
- WHEN Flint opens or edits a provider-backed vault
- THEN evidence distinguishes bookmark/security-scope setup, coordination wait, accessor work, enumeration, metadata, previews, note reads/writes, markdown conversion, image read/decode/import, and first usable screen
- AND stage durations, counts, observed bytes, memory warnings, and save outcomes are recorded where available
- AND each operation has one logical terminal outcome; late completion is a separate observation
- AND profiling intervals allow matching the journal to a device performance trace

### Requirement: Exclude private document data
The system SHALL persist and export only allowlisted fields, bounded error-domain/code chains, and launch-scoped opaque resource IDs. Content, paths, titles, captions, image bytes, bookmarks, accounts, credentials, unrestricted error descriptions, and raw error dictionaries SHALL be excluded.

#### Scenario: Optional preview read fails
- WHEN a preview or metadata lookup fails and uses a fallback
- THEN evidence distinguishes failure from a successful empty read and includes its stage and sanitized error codes
- AND missing, unavailable, permission, coordination, bookmark, and decode errors are distinguished only when supported by evidence
- AND provider/download state is unknown when unavailable; paths and iCloud-only keys do not establish Dropbox materialization state

### Requirement: Bound persistence and diagnostic overhead
The system SHALL keep versioned diagnostics in protected app-local storage outside the vault, limited to 20 MiB and seven days with oldest-first rotation. Diagnostic collection SHALL perform no provider reads or synchronous main-thread disk writes and SHALL degrade without blocking document operations.

#### Scenario: Storage is slow, full, expired, or corrupt
- WHEN the diagnostic writer falls behind or storage fails
- THEN at most 512 events are pending, ordinary records are at most 16 KiB, and segments are at most 256 KiB
- AND excess or oversized events are dropped with bounded accounting rather than blocking callers
- AND incomplete records do not prevent relaunch, and expired/old records are removed first
- AND storage failures do not recursively log or crash the app

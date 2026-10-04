# crash-recovery Specification

## Purpose

Define platform crash and hang evidence, interrupted-restoration recovery, and user-controlled local diagnostic export.

Status: planned; the associated change's unchecked tasks identify implementation and validation still required.

## Requirements

### Requirement: Collect independent termination and responsiveness evidence
The system SHALL collect available platform crash, hang, CPU and disk-write reports, preserving event windows and binary/build identity separately from receipt time. Missing or delayed reports SHALL be expected. Release symbol files SHALL be retained; an unclean launch marker SHALL NOT establish a crash or its cause.

#### Scenario: Evidence arrives after a hard termination
- WHEN a platform report arrives on another launch
- THEN sanitized reports are deduplicated and correlated only when timestamps and build evidence support it
- AND unknown correlation and missing reports are explicit
- AND no arbitrary Swift recovery is attempted in a native signal handler
- AND device crash, watchdog and jetsam collection and matching-symbol procedures are documented

#### Scenario: Foreground responsiveness stops
- WHEN the main-thread heartbeat is delayed by at least two seconds
- THEN an independent monitor records one suspected stall with active operation context and recovery duration when available
- AND it excludes background suspension and bounds repeated events
- AND a slow provider operation is observable without needing the main actor or blocked worker to run

### Requirement: Recover before repeating an interrupted restoration
The system SHALL durably mark automatic restoration before provider access and record completion or handled abandonment. An unfinished restoration SHALL show Retry, Choose another vault, and Export diagnostics before repeating provider access. Recovery SHALL preserve bookmarks and provider files.

#### Scenario: Relaunch after interrupted provider access
- WHEN the previous restoration marker is unfinished or a new safety marker cannot be persisted
- THEN recovery appears before automatic restoration and describes an interrupted attempt without asserting a crash cause
- AND the user can choose a different vault or export without reading the provider
- AND explicit retry remains available, subject to bounded execution rules

### Requirement: Export only under user control
The system SHALL offer a versioned, sanitized local diagnostic bundle from onboarding, recovery and ready state, with category/time-range preview, system sharing and clear-history controls. No telemetry SHALL upload automatically.

#### Scenario: Export while provider access is stalled
- WHEN the user exports diagnostics
- THEN only app-local events, performance summaries, sanitized platform reports, previous-launch state, build, OS and device-model information are used
- AND missing/dropped records, uncertain termination causes and collection limitations are stated
- AND raw platform payloads and error dictionaries are not shared
- AND export failure is recoverable, only one bounded 20 MiB temporary bundle exists, and it is cleaned after sharing/cancellation or next launch
- AND clearing history resets retained evidence and IDs while preserving bookmarks, document-recovery copies and a minimal current safety marker

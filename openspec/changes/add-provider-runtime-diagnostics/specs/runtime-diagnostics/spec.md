# runtime-diagnostics Specification

## Purpose

Define the intended logging, local performance telemetry, crash evidence, and recovery behavior needed to diagnose physical-device failures with partially downloaded Files-provider vaults. These requirements are planned; their presence does not claim that diagnostics are already implemented.

## ADDED Requirements

### Requirement: Correlate structured runtime events

The system SHALL record structured diagnostics in Debug and Release builds from process startup, before bookmark restoration or provider access. Events SHALL include schema version, UTC timestamp, monotonic elapsed time, severity, category, build/version, launch identifier, operation identifier, parent operation identifier where applicable, stage, and outcome. Operation outcomes SHALL distinguish success, failure, cancellation, timeout, and abandoned work.

#### Scenario: Trace a provider-backed launch

- WHEN Flint restores a vault
- THEN correlated events cover bookmark resolution, security-scoped access, coordination wait, enumeration, metadata lookup, preview reads, initial note read, markdown conversion, image loading, and first usable screen
- AND coordination wait is distinguishable from time spent inside its accessor
- AND every completed operation has one terminal outcome
- AND late worker completion after timeout is recorded separately without a second terminal outcome

### Requirement: Preserve actionable errors without private content

The system SHALL record sanitized error domains, codes, bounded underlying-error chains, operation stages, and available provider observations. It SHALL distinguish unavailable content, missing files, permission failures, coordination failures, invalid bookmarks, decode failures, and unknown errors when evidence supports those distinctions. It SHALL NOT infer Dropbox or download state from a path or assume iCloud resource keys describe third-party provider availability.

#### Scenario: Preview generation fails

- WHEN an optional preview or metadata read fails
- THEN Flint records the failure even if the note list uses a fallback
- AND the event distinguishes the fallback from an empty successful read
- AND provider and materialization observations are marked unknown when unavailable

#### Scenario: Error includes sensitive information

- WHEN an error contains note text, a filename, a path, or a provider account identifier
- THEN persisted and exported diagnostics contain only allowlisted fields and opaque resource identifiers
- AND note contents, titles, image contents, alt text, absolute or relative paths, bookmark data, credentials, and unrestricted localized error text are excluded
- AND resource identifiers are scoped to a launch rather than stable user tracking identifiers

### Requirement: Measure performance without creating another stall

The system SHALL measure launch duration, time to first usable screen, coordination wait and accessor duration, enumeration counts and progress, preview/read/decode durations, observed byte counts, save outcomes, memory warnings, and foreground main-thread responsiveness. Signpost intervals SHALL allow device profiling. Diagnostics SHALL NOT read provider files or synchronously write logs on the main thread.

#### Scenario: Provider blocks during enumeration

- GIVEN a provider operation stops progressing
- WHEN it exceeds 5 seconds of foreground elapsed time
- THEN an independent monitor records one slow-operation event with the last completed stage and available counters
- AND the monitor does not require the stalled worker or main actor to make progress

#### Scenario: Main thread becomes unresponsive

- GIVEN Flint is foreground-active
- WHEN a main-thread heartbeat is delayed by at least 2 seconds
- THEN an independent monitor records a suspected stall with the active operation identifiers
- AND a recovery event records the observed duration when responsiveness returns
- AND background suspension is excluded and long stalls produce bounded event volume
- AND a heartbeat delay alone is not labeled a confirmed crash

### Requirement: Keep local diagnostic storage bounded and independent of the vault

The system SHALL retain sanitized versioned diagnostics and launch markers in protected app-local storage outside the vault. Retention SHALL be limited to 20 MiB and 7 days, tolerate incomplete records, and rotate oldest records first. A fixed-capacity event queue SHALL drop records with truncation accounting rather than blocking user operations under backpressure.

#### Scenario: Logging storage is unavailable

- WHEN local storage is full, unavailable, corrupt, or an event exceeds the size limit
- THEN diagnostics degrade without crashing or blocking vault operations
- AND diagnostics do not recursively log their own failures
- AND a corrupt journal does not prevent startup or recovery

### Requirement: Collect platform crash and hang evidence

The system SHALL collect available platform performance and diagnostic evidence from early launch and retain sanitized crash, hang, CPU, and disk-write reports when delivered. Reports SHALL preserve event time windows and build identity separately from receipt time. Missing or delayed reports SHALL be expected; matching release symbol files SHALL be retained for investigation.

#### Scenario: Hard termination occurs before a final log can be written

- WHEN iOS terminates Flint or a native crash occurs
- THEN Flint relies on pre-existing breadcrumbs and platform crash evidence rather than executing arbitrary Swift recovery in a signal handler
- AND the next launch preserves the interrupted launch context
- AND an unmatched launch marker is classified as an unclean previous session, not proof of a crash or its cause

#### Scenario: Platform evidence arrives later

- WHEN a diagnostic payload is delivered on a later launch
- THEN Flint stores its original event time range, binary identity, diagnostic kind, and sanitized call-stack evidence
- AND it records correlation confidence rather than attributing the payload to the current launch
- AND duplicate deliveries do not duplicate stored reports

### Requirement: Bound provider-backed loading and offer recovery

The system SHALL keep provider work off the main actor with bounded capacity, progress, and cancellation. Vault opening SHALL expose a slow state after 5 seconds and become usable or recoverable within 30 seconds of foreground-active time. Timed-out attempts SHALL be invalidated without waiting for blocked accessors; stale results SHALL not change current state and access SHALL remain valid until work stops.

#### Scenario: Partially downloaded Dropbox vault stalls

- GIVEN a selected vault contains unavailable or partially downloaded provider files
- WHEN opening cannot finish within the loading deadline
- THEN Flint exits the indefinite loading presentation and offers Retry, Choose another vault, and Export diagnostics
- AND it preserves the saved bookmark unless bookmark resolution independently proves it unusable
- AND it records the timed-out stage and attempt identifier
- AND Retry does not create unbounded workers while prior provider work remains blocked
- AND another vault can be selected without waiting for the timed-out worker

#### Scenario: Content is unavailable while saving or reading

- WHEN a provider-backed note read or save fails
- THEN Flint records the failure and presents a recoverable error
- AND a failed save retains unsaved editor text for retry
- AND a failed read does not become an empty successful note or overwrite the source
- AND diagnostics collection does not download the entire vault to inspect availability

### Requirement: Avoid repeated automatic restoration failures

The system SHALL durably mark the start of each automatic vault restoration before provider access and mark its completion or handled abandonment. If a previous restoration marker remains unfinished, the next launch SHALL offer recovery before automatically reopening that vault. Recovery SHALL work without accessing the provider or deleting its bookmark or files.

#### Scenario: Relaunch after a suspected launch crash or freeze

- GIVEN the previous launch ended during automatic vault restoration
- WHEN Flint launches again
- THEN Flint presents a recovery screen with Retry, Choose another vault, and Export diagnostics
- AND it describes an interrupted launch without asserting an unproven crash cause
- AND it does not immediately repeat the failing provider operation

### Requirement: Export diagnostic evidence under user control

The system SHALL offer a user-initiated bounded diagnostic export from onboarding, loading recovery, and ready state, with category/time-range preview, system sharing, and clear-history controls. No telemetry SHALL upload automatically. The versioned bundle SHALL contain sanitized local evidence and disclose missing reports and collection limitations.

#### Scenario: Bundle includes interpretable context

- WHEN Flint creates an export
- THEN it includes sanitized events, performance summaries, available platform reports, previous-launch status, build, OS, and device-model information
- AND it discloses collection limitations and uncertain correlations
- AND a bounded temporary bundle is removed after sharing or cancellation, or on the next launch

#### Scenario: Export while a provider is stalled

- WHEN the user exports diagnostics from recovery
- THEN bundle creation uses only app-local data and does not read the vault
- AND the bundle indicates dropped records, absent platform reports, and uncertain termination causes
- AND raw platform payloads or error dictionaries are not shared without sanitization
- AND export failure remains recoverable
- AND clearing history removes retained bundles and resets identifiers while preserving a minimal current launch-safety marker

### Requirement: Validate diagnostics and recovery against provider faults

The change SHALL include deterministic tests for blocking coordination before an accessor, blocking inside an accessor, unavailable content, permission denial, partial enumeration, decode failure, failed writes, late completion, diagnostics disk failure, corrupt history, and interrupted restoration. Physical-iPhone validation with a Dropbox Files-provider vault SHALL be recorded before the change is considered validated.

#### Scenario: Simulator fault coverage

- WHEN the required full Flint simulator suite runs
- THEN diagnostics and recovery tests run without a real Dropbox account
- AND controlled clocks verify slow thresholds, deadlines, cancellation, and foreground suspension handling
- AND tests assert event correlation, bounded queues/storage, content redaction, retained unsaved text, recovery availability, and rejection of stale results

#### Scenario: Physical-device acceptance

- GIVEN an iPhone with a Dropbox vault containing downloaded and not-yet-downloaded notes and images
- WHEN launch and reopen are exercised online, offline, during a download, and after termination during restoration
- THEN a recording identifies the build, device/iOS version, provider version when available, and fixture conditions
- AND the app remains interactive or enters recovery within the deadline without losing note data
- AND exported evidence identifies the last stage and distinguishes coordination wait from read/decode work
- AND an Instruments trace and available crash/watchdog/jetsam reports are attached to the validation record
- AND absent platform reports are recorded as absent rather than treated as evidence of no crash

### Requirement: Persist restoration safety before automatic access

Restoration safety storage SHALL use a dedicated app-local writer and a one-second maximum asynchronous wait. A versioned marker SHALL contain only launch/action IDs, timestamps, and started/completed/abandoned state. Missing storage is safe only when no marker exists; corrupt or unreadable storage and failed/timed-out writes SHALL require explicit recovery. Late writer completion SHALL not authorize provider work. At most one safety request SHALL be admitted until its writer actually completes; repeated retry SHALL fail safely rather than queue more writes. Retry SHALL be explicit; choosing another vault SHALL preserve the saved bookmark until a new selection is made.

#### Scenario: Safety storage fails

- WHEN checking or committing a restoration marker fails or exceeds one second
- THEN automatic bookmark resolution and provider access do not begin
- AND recovery explains that safe automatic restoration was unavailable
- AND explicit retry or choosing a vault remains available without clearing saved permission data

### Requirement: Bound and sanitize platform evidence

MetricKit ingestion SHALL use a serial app-local writer with at most eight waiting deliveries. Only original report windows, validated app version/build identities, diagnostic kinds, numeric aggregate measurements, UUIDs, stack/thread topology, and numeric stack-frame fields SHALL be retained. Binary names, exception descriptions, arbitrary metadata and signpost strings SHALL be omitted. Unknown build correlation SHALL stay unknown, and receiving launch IDs SHALL never be treated as the report's originating launch. Sanitized reports SHALL deduplicate by canonical content and share the journal's aggregate 20 MiB/seven-day retention budget.

#### Scenario: Older delivery contains private fields

- WHEN a payload from an earlier build/time window arrives with private strings
- THEN receipt time is separate from the original report window
- AND no current-launch attribution or private strings are persisted
- AND repeat delivery produces one retained report

### Requirement: Independently observe foreground progress

A utility timer SHALL inspect a thread-safe action snapshot and schedule at most one outstanding main-queue heartbeat. Each action SHALL emit at most one slow observation after five foreground seconds. A heartbeat gap of two seconds SHALL emit one suspected stall and one recovery duration; inactive transitions SHALL reset heartbeat gaps and pause action accumulation. Monitoring SHALL not depend on the log writer, provider workers, or main actor for sampling.

#### Scenario: Suspension overlaps a pending heartbeat

- WHEN the app leaves the foreground and later returns
- THEN time suspended is excluded from action elapsed time
- AND stale heartbeat acknowledgments do not create a stall or recovery for suspension

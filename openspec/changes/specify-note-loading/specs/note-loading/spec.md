# note-loading Specification

## Purpose

Define incremental note discovery, lazy bounded previews, pending content states and revision-safe persistence for provider vaults.

Status: planned; the associated change's unchecked tasks identify implementation and validation still required.

## ADDED Requirements

### Requirement: Discover metadata before content
The system SHALL publish note metadata in bounded batches without eagerly reading every preview or image, preserving extensions, regular-file/hidden-file filters, relative paths and existing sort rules. Batch work SHALL yield capacity to explicit reads/writes. Partial discovery SHALL remain usable and visibly incomplete on failure.

#### Scenario: Optional content is unavailable
- WHEN some metadata or preview reads fail or stall
- THEN discovered notes remain usable, failures are recorded and previews show pending/unavailable states
- AND previews are requested only for visible/recently requested notes, read at most 64 KiB, and decode only complete UTF-8 sequences
- AND the preview cache stays within 4 MiB and invalidates on observed version change or explicit refresh
- AND omitted, truncated and empty previews remain distinguishable

### Requirement: Load selected content explicitly and safely
The system SHALL separately expose selected-note loading with cancellable generation identity. It SHALL auto-select once from current sorted metadata when needed, without later batches overriding user selection. Editable note reads SHALL enforce an 8 MiB source limit during reading; failed/partial reads SHALL never become empty editable documents.

#### Scenario: First note is unavailable or oversized
- WHEN its content cannot be loaded or exceeds the size limit, including growth during reading
- THEN the browser stays usable and shows pending or recoverable note state
- AND another note can be selected without a stale fallback overriding it
- AND partial text cannot be saved over the source and original markdown is unchanged
- AND preparing markdown does not synchronously read referenced images

### Requirement: Preserve edits and write identity
The system SHALL capture original destination, access lease, text revision and operation ID for ordered debounced saves. Completion SHALL clear dirty state only for the saved current revision. Failed/timed-out writes SHALL retain text, and navigation SHALL persist it or obtain an explicit retain/discard decision.

#### Scenario: Typing or navigation overlaps saving
- WHEN newer edits arrive during a write
- THEN old completion cannot overwrite or mark the new revision saved
- AND a timed-out write has an uncertain outcome, retains its original destination, and cannot overlap a retry
- AND navigation resolves persistence or retains a protected local recovery copy separate from diagnostics, unless the user explicitly discards it
- AND metadata refresh does not reload editor content or convert a successful write into a failed-write claim
- AND switching vault cannot write previous text into the new vault

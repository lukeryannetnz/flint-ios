# provider-file-access Specification

## Purpose

Define intended responsive, bounded, and data-safe file access for local and Files-provider vaults, including partially downloaded Dropbox content. These requirements are planned and do not claim implementation is complete.

## ADDED Requirements

### Requirement: Isolate blocking file and image work from the main actor

The system SHALL perform bookmark resolution/creation, security-scoped resource acquisition, file coordination, enumeration, resource metadata lookup, note and preview reads, note/vault creation, note writes, image import/copy/encoding, image file reads, and image decoding outside the main actor. UI state publication and UIKit view updates SHALL remain on the main actor. Wrapping synchronous work in a main-actor Task SHALL NOT satisfy this requirement.

#### Scenario: Restore a provider-backed vault

- WHEN Flint opens a saved Dropbox vault whose files are partially downloaded
- THEN waiting for the provider does not block rendering, taps, loading progress, cancellation, or diagnostics export
- AND bookmark and security-scope setup do not perform synchronous provider work on the UI thread
- AND file coordination continues to protect provider-backed reads and writes

### Requirement: Bound loading attempts and cancellation

The system SHALL expose cancellable loading, a slow state after 5 seconds, and a usable screen or recoverable failure within 30 seconds of foreground-active time. Foreground note/image reads and imports SHALL use the same deadline. Attempts SHALL reject stale completion, keep access valid until workers stop, and use bounded work capacity. Background suspension SHALL pause UI deadlines.

#### Scenario: Bound queued and active provider work

- WHEN provider work is scheduled or retried
- THEN no more than two blocking jobs run globally and no more than one runs for a given vault
- AND no more than 32 jobs wait in the pending queue
- AND cancelled queued jobs are removed
- AND deadlines request cancellation without assuming an already-running accessor has stopped
- AND every attempt carries an identity that rejects stale completion

#### Scenario: Accessor remains blocked after timeout

- GIVEN one vault operation is still blocked inside an accessor
- WHEN the loading deadline expires
- THEN the UI offers Retry, Choose another vault, and Export diagnostics without awaiting that accessor
- AND another vault can use the remaining worker slot
- AND retrying the same vault reports that previous work is still stopping instead of adding concurrent jobs for that vault
- AND if both slots are blocked, selecting another vault returns a recoverable busy state without creating more workers
- AND late success or failure cannot replace the current vault, text, selection, or alert
- AND security-scoped access used by the worker is released only after its actual completion

### Requirement: Discover notes without eagerly reading all content

The system SHALL discover note metadata incrementally without eagerly reading content, preserve supported file filters and sort rules, and publish usable partial results. Previews SHALL be demand-driven with bounded reads and caching. Progress SHALL report observed counts and stages without inventing a total or download percentage. Automatic discovery continuation and visible preview requests SHALL not acquire the vault lane before the initial selected-content read has completed logically, including while restoration safety completion awaits. Each discovery batch SHALL contain at most 64 notes and examine at most 256 entries, release its worker slot between batches, and admit explicit reads ahead of optional continuation work. Metadata failures SHALL be diagnosed and mark discovery incomplete without removing usable results.

#### Scenario: A complete refresh supersedes an older discovery

- WHEN creation or a save publishes a newer complete metadata listing
- THEN the older incremental cursor is invalidated before that listing is published
- AND late cursor completion cannot remove newly created notes or restore obsolete metadata

#### Scenario: Bound preview work

- WHEN visible or recently requested notes need previews
- THEN each preview reads no more than 64 KiB of source and decodes only complete UTF-8 sequences
- AND omitted, truncated, and unavailable previews are distinguishable
- AND exact 64 KiB sources are complete previews when a coordinated end-offset check establishes EOF without reading another source byte
- AND the preview cache stays within 4 MiB and invalidates on observed content-version changes, successful saves, or explicit refresh
- AND offscreen preview demand is cancelled and stale preview results cannot replace a newer version
- AND an empty successful source is distinguished from a preview omitted before demand
- AND discovery preserves regular-file filtering, hidden-file exclusion, supported extensions, relative paths, and existing sort rules

#### Scenario: One provider item is unavailable

- GIVEN enumeration has produced usable note metadata
- WHEN a metadata or preview lookup for another item fails or stalls
- THEN already discovered notes remain available
- AND affected previews use an unavailable or pending state rather than blocking the browser
- AND the failure is recorded with its operation stage
- AND discovery failure after partial progress is visible and retryable

### Requirement: Select initial content without forcing a download of every note

The system SHALL show the browser once usable metadata is available and separately expose selected-note loading. It SHALL choose the first available note according to the existing ordering when no selection can be preserved, but SHALL allow cancellation or selection of another note while that content is unavailable. Reading failures SHALL NOT masquerade as empty notes.

#### Scenario: First note content is not available

- WHEN Flint discovers a note but cannot finish reading its content
- THEN the browser remains usable with a pending or recoverable selected-note state
- AND the editor does not permit saving placeholder text over that file
- AND other discovered notes can be selected
- AND no background fallback selection overrides a later user selection

### Requirement: Preserve edits across asynchronous saves and navigation

The system SHALL capture destination, access lease, text revision, and operation identity for ordered, debounced saves. Completion SHALL clear dirty state only for the current revision. Failed or timed-out writes SHALL retain edits; timed-out writes SHALL report uncertain outcomes and prohibit overlapping retries. Navigation SHALL persist edits or obtain an explicit retain/discard choice.

#### Scenario: Retry after an uncertain write

- WHEN a write exceeds its deadline while its accessor remains active
- THEN Flint retains text and dirty state and reports an uncertain outcome
- AND retry waits for the original write to finish rather than overlapping it
- AND save identity retains its original destination and lease
- AND choosing to retain edits creates a local recovery copy separate from diagnostics

#### Scenario: User types while a save is in progress

- GIVEN revision A is being written
- WHEN the user creates revision B before A finishes
- THEN completion of A does not mark B saved or overwrite B in the editor
- AND B remains eligible for a subsequent ordered autosave

#### Scenario: User changes vault with pending edits

- WHEN the user switches vault while edits or a write are pending
- THEN Flint resolves the save or obtains an explicit retain/discard choice before replacing editor state
- AND the old operation retains its original destination and cannot write into the new vault
- AND cancellation does not claim that an already-running write was rolled back

### Requirement: Bound editable note content

The system SHALL limit a single editable note read to 8 MiB of source bytes, enforce the limit during the read even when size metadata is absent, and report an oversized note as a recoverable read failure. It SHALL NOT silently truncate editable markdown or permit saving a partial read over its source. Markdown preparation SHALL not synchronously read referenced assets.

#### Scenario: Missing or stale size metadata

- WHEN size metadata is missing or a source grows after discovery
- THEN reads still enforce the 8 MiB limit from actual bytes using bounded chunks
- AND invalid UTF-8 or an interrupted read never becomes an editable document

#### Scenario: Large or growing provider note

- WHEN the source exceeds the editable-note limit or grows beyond it during loading
- THEN Flint stops accumulating source bytes and shows a size-limit error
- AND the browser remains usable
- AND the file is unchanged and cannot be overwritten through a partial editor document

### Requirement: Load and decode images lazily with bounded memory

The system SHALL resolve, load, and downsample images asynchronously, show stable pending placeholders, and perform no provider reads or decoding in layout or initial text construction. Image work and cache memory SHALL remain bounded and respond to memory warnings. File/version and target-size caching SHALL avoid source rereads during ordinary relayout.

#### Scenario: Bound decode and cache resources

- WHEN image requests are processed
- THEN no more than one image decode is active
- AND decoded thumbnails have a longest edge of at most 2048 pixels and viewer images at most 4096 pixels
- AND downsampling does not first decode a full-resolution source image
- AND reusable decoded images consume at most 32 MiB of cache memory
- AND memory warnings evict reusable images and cancel optional queued work

#### Scenario: Large provider image appears in a note

- WHEN an inline image is not yet downloaded or has a large source resolution
- THEN text renders and remains interactive while the image loads
- AND layout does not synchronously request source bytes or decode the image
- AND successful completion updates only an attachment belonging to the current document generation
- AND the caption and stored markdown reference remain unchanged
- AND unavailable, invalid, or failed images retain a readable placeholder and retry affordance

#### Scenario: Viewer opens during image loading

- WHEN the user opens an image in the fullscreen viewer
- THEN the viewer shows progress and permits dismissal while the image is read and downsampled
- AND a late completion cannot reopen a dismissed viewer or affect another note

### Requirement: Import images without blocking editing or losing managed assets

The system SHALL copy or encode selected image sources into managed vault assets off the main actor and insert markdown only after a successful import for the current document generation. The import SHALL retain required source and destination access for its actual duration. A failed or cancelled import SHALL not report successful insertion; any completed but unreferenced asset SHALL be handled separately without deleting assets referenced by unsaved or saved text.

#### Scenario: Provider source becomes unavailable during import

- WHEN an image source read or managed-asset write fails
- THEN the editor remains responsive and retains its original text and insertion intent
- AND Flint records the failed stage and offers a retryable error
- AND a late import cannot insert an image into a different note

### Requirement: Verify responsiveness and data integrity

The implementation SHALL include deterministic tests with controllable blocking reads/writes, clocks, cancellation, queue saturation, stale completion, preview budgets, revision ordering, large image sources, and memory warnings. It SHALL record physical-iPhone Dropbox validation and an Instruments trace before the change is considered validated.

#### Scenario: Device performance acceptance

- GIVEN fully downloaded and partially downloaded Dropbox vault fixtures with large notes and images
- WHEN launch, scrolling, note switching, autosave, image insertion, and viewer dismissal are exercised online and offline
- THEN no provider wait or image decode appears on the main-thread trace
- AND stalled loading exposes recovery within 30 seconds of foreground-active time
- AND taps and scrolling remain responsive during delayed I/O
- AND memory and concurrency stay within the stated budgets
- AND saved markdown and referenced assets remain intact after failure, retry, and relaunch

### Requirement: Carry explicit asynchronous request identity

Vault-file methods SHALL accept a request carrying vault-root identity, foreground deadline, priority and attempt identity, and SHALL return asynchronously with a value or typed cancellation/timeout/capacity failure. Bookmark resolution and creation SHALL use the same bounded executor. A loading attempt SHALL share a single 30-second foreground budget across setup, discovery and initial content; starting another stage SHALL not reset it.

#### Scenario: Late setup completion

- WHEN bookmark or scope acquisition finishes after its attempt was cancelled or timed out
- THEN no later provider stage is dispatched for that attempt
- AND no bookmark, vault, selection, busy state or alert belonging to a newer attempt is replaced

#### Scenario: Scope acquisition finishes after cancellation

- WHEN acquiring the first resource scope blocks and the attempt is cancelled or times out
- THEN logical recovery does not wait for acquisition
- AND eventual acquisition is balanced without acquiring subsequent source scopes or entering another provider stage

### Requirement: Keep uncertain mutations separate from retries

The executor SHALL retain an actual mutation outcome for the owning attempt after logical timeout or cancellation. A retry SHALL first establish whether the original write/create finished, without issuing another mutation while it drains. Saves SHALL snapshot their original text, destination and revision; an asynchronous completion SHALL not clear newer edits. Navigation SHALL first save dirty text and remain at its original destination if saving cannot be established. Explicit retain/discard recovery storage is added in phase 4.

#### Scenario: A late save is confirmed successful

- WHEN an uncertain save later has an actual successful result
- THEN its note preview and visible demand are invalidated as for an ordinary success
- AND metadata finalization uses a fresh foreground attempt rather than the expired mutation attempt
- AND newer dirty revisions remain eligible for ordered persistence

#### Scenario: Creation finishes after its deadline

- WHEN the user retries a timed-out creation
- THEN pending work is described as still stopping
- AND actual success opens the already-created result rather than creating a duplicate
- AND only actual failure or a request that never started permits a new create attempt

### Requirement: Keep recovery actions usable during blocked file access

Loading SHALL publish current stage and a slow indicator, allow cancellation, and transition to recovery independently of blocked workers. Recovery SHALL support retry, choosing another vault, and exporting sanitized app-local evidence. A minimal bounded sharing action SHALL be available in phase 3; category/time-range preview and clear-history controls are added in phase 6.

#### Scenario: Provider workers are both occupied

- WHEN a new explicit attempt cannot acquire bounded capacity
- THEN the UI reports busy recovery immediately
- AND it creates no extra provider threads or unbounded queued retries
- AND local diagnostic sharing remains available

### Requirement: Retain successful creation through follow-up failure

A successful note creation SHALL retain its destination URL until discovery and selection succeed. Retrying the same creation name and folder after refresh/read failure SHALL reuse that result and SHALL not issue another create mutation. Switching vault generations SHALL discard obsolete creation presentation state.

#### Scenario: Navigation changes while creation awaits

- WHEN creation succeeds after the user selects another note in the same vault
- THEN the destination URL is retained before stale navigation is rejected
- AND the newer selection remains unchanged
- AND retrying the same name and folder opens the existing result without another create mutation

#### Scenario: Refresh fails after creation

- WHEN note creation succeeds and discovery fails or times out
- THEN retry refreshes and opens the already-created note
- AND no duplicate creation is attempted

#### Scenario: Dirty editor prevents opening a created note

- WHEN edits made while creation refresh awaits cannot be saved before navigation
- THEN the previous editor retains its text and destination
- AND the creation busy indicator clears
- AND the created URL remains available for retry

### Requirement: Recover typed late image outcomes

Actual mutation outcomes SHALL preserve created URLs, complete image-import results and valueless saves as distinct typed values. During the current process, the model SHALL retain timed-out or stale successful imports by their original note URL. Another import for a note with unresolved outcomes SHALL not create a replacement asset. Explicit recovery in that original note SHALL insert the completed result at the current cursor once, without copying or encoding again. A running import SHALL remain pending; an actual failure SHALL permit a new source selection. Navigation SHALL not discard a pending result or insert it into another note. No recovery path SHALL delete a referenced asset. Durable pending-asset reconciliation across relaunch remains part of the later image workflow.

#### Scenario: Image import succeeds after timeout

- WHEN a file or camera import times out and subsequently finishes
- THEN its full Markdown, asset URL and alt text remain available
- AND Recover image reuses that completed result without another provider mutation
- AND switching notes cannot insert the late result into the new note

#### Scenario: Repeated source callback while an import is active

- WHEN another file or camera callback arrives before the first import returns
- THEN the first request is registered as in flight before provider dispatch
- AND the second callback cannot create another asset or clear the first request's busy state

#### Scenario: Actual late failure permits a fresh source

- WHEN a timed-out import has actually failed or never started
- THEN a new source selection removes that resolved failure before admission
- AND no Recover action is required to start the replacement

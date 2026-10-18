# provider-file-access Specification

## Purpose

Users may open a vault whose files are slow to download or temporarily unavailable. Waiting for a file provider such as Dropbox must not freeze Flint or put unsaved edits at risk. Users need to browse available notes, cancel stalled work, and recover their edits.

This spec defines file access, loading limits, saves, and recovery.

A worker runs file operations away from the screen-update thread. The executor schedules those workers with fixed capacity. An access lease keeps iOS file permission active until a worker finishes. A deadline limits how long the user waits; it does not prove that a file operation has stopped. Foreground-active time counts only while Flint is active on screen. A generation identifies the current vault, note, or screen so older results cannot replace newer state.

Status: bounded asynchronous file access, incremental note loading, previews requested by visible rows, and persistent recovery copies are implemented and simulator-tested. Prepared image loading remains planned. Physical-iPhone Dropbox acceptance is still pending. The complete specification is not yet implemented.

## Requirements

### Requirement: Phase 4 loading and document recovery contract

Flint SHALL inspect and publish at most 64 file entries in each discovery batch. Between batches, it SHALL let other provider work use the worker capacity. The browser SHALL show notes as they are found. If discovery is incomplete, it SHALL offer cancellation and retry. It SHALL choose an initial note once, from the first usable sorted batch, unless the user has already chosen one.

Reading the selected note SHALL have its own foreground deadline. Only visible rows SHALL request previews. Each preview SHALL read at most 64 KiB of source. The preview cache SHALL hold at most 4 MiB and track content versions. Editable notes SHALL be limited to 8 MiB, with that limit enforced during reading even if file size details are unreliable.

If saving before navigation fails, Flint SHALL offer Stay, Retain edits and continue, and Discard edits and continue. Before continuing after Retain, it SHALL save a protected recovery copy in app-local storage. The write SHALL be atomic: either the complete record is saved or navigation does not proceed. The record SHALL contain the original vault, note destination, and exact text.

Recovery copies SHALL survive relaunch and remain separate from diagnostic exports. The recovery list SHALL show each copy's original destination and offer explicit restore and delete actions. Restore SHALL require the matching vault and note. It SHALL never overwrite provider content automatically.

Discard SHALL explain that a write already in progress may still finish. If a write's outcome is uncertain, Flint SHALL prevent another save to that destination from overlapping it, even after navigation.

#### Scenario: Discovery fails after a batch

- WHEN a later batch fails after metadata has been published
- THEN the browser retains discovered notes and shows incomplete discovery with Retry
- AND an empty list during discovery or after failure is not presented as an empty-vault success

#### Scenario: Retained edits survive relaunch

- WHEN the user retains edits after a failed save and relaunches Flint
- THEN the recovery list identifies the original destination and restores the exact retained text only into that note
- AND failed recovery storage leaves the current unsaved editor intact

### Requirement: Keep blocking file and image work off the screen-update thread

The system SHALL perform bookmark resolution/creation, security-scoped resource acquisition, file coordination, enumeration, resource metadata lookup, note and preview reads, note/vault creation, note writes, image import/copy/encoding, image file reads, and image decoding outside the main actor.

UI state publication and UIKit view updates SHALL remain on the main actor.

Wrapping synchronous work in a main-actor Task SHALL NOT satisfy this requirement.

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

The system SHALL discover note metadata incrementally without eagerly reading content, preserve supported file filters and sort rules, and publish usable partial results. Previews SHALL be demand-driven with bounded reads and caching. Progress SHALL report observed counts and stages without inventing a total or download percentage.

#### Scenario: Bound preview work

- WHEN visible or recently requested notes need previews
- THEN each preview reads no more than 64 KiB of source and decodes only complete UTF-8 sequences
- AND omitted, truncated, and unavailable previews are distinguishable
- AND the preview cache stays within 4 MiB and invalidates on observed content-version changes or explicit refresh
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

For each save, Flint SHALL capture the destination, access lease, text revision, and operation identity. Saves SHALL run in order after the typing pause used for autosave. A completed save SHALL clear unsaved state only if it saved the current text revision.

Failed or timed-out writes SHALL retain edits. A timed-out write SHALL report that its outcome is uncertain and prevent overlapping retries. Before navigation, Flint SHALL save edits or obtain an explicit choice to retain or discard them.

#### Scenario: Retry after an uncertain write

- WHEN a write exceeds its deadline while its accessor remains active
- THEN Flint retains text and unsaved state and reports an uncertain outcome
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
- AND unavailable, invalid, or failed images retain a readable placeholder and way to retry

#### Scenario: Viewer opens during image loading

- WHEN the user opens an image in the fullscreen viewer
- THEN the viewer shows progress and permits dismissal while the image is read and downsampled
- AND a late completion cannot reopen a dismissed viewer or affect another note

### Requirement: Import images without blocking editing or losing managed assets

The system SHALL copy or encode selected image sources into managed vault assets off the main actor and insert markdown only after a successful import for the current document generation.

The import SHALL retain required source and destination access for its actual duration.

A failed or cancelled import SHALL not report successful insertion; any completed but unreferenced asset SHALL be handled separately without deleting assets referenced by unsaved or saved text.

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

Each vault-file request SHALL identify its vault root, foreground deadline, priority, and attempt. It SHALL return asynchronously with a value or a typed failure that distinguishes cancellation, timeout, and lack of capacity. Resolving and creating bookmarks SHALL use the same executor with bounded worker capacity.

A loading attempt SHALL share one 30-second foreground budget across setup, discovery, and initial content. Starting another stage SHALL not reset that budget.

#### Scenario: Late setup completion

- WHEN bookmark or scope acquisition finishes after its attempt was cancelled or timed out
- THEN no later provider stage is dispatched for that attempt
- AND no bookmark, vault, selection, busy state or alert belonging to a newer attempt is replaced

#### Scenario: Scope acquisition finishes after cancellation

- WHEN acquiring the first resource scope blocks and the attempt is cancelled or times out
- THEN logical recovery does not wait for acquisition
- AND eventual acquisition is balanced without acquiring subsequent source scopes or entering another provider stage

### Requirement: Keep uncertain mutations separate from retries

A mutation is an operation that changes a file, such as saving or creating it. After a timeout or cancellation, the executor SHALL keep the mutation's actual outcome for the attempt that started it. A retry SHALL first check whether the original operation finished. It SHALL not issue another mutation while the original is still running.

Saves SHALL capture their original text, destination, and revision. A later completion SHALL not clear newer edits. Before navigation, Flint SHALL save unsaved text. If saving cannot be confirmed, it SHALL stay at the original destination unless the user explicitly retains or discards edits through phase 4 recovery.

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

### Requirement: Remember a created note if the next step fails

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

### Requirement: Recover image imports that finish late

Mutation results SHALL distinguish a created URL, a complete image-import result, and a save that returns no value.

During the current process, Flint SHALL retain successful image imports that finish after timeout or become stale after navigation. Each result SHALL stay associated with its original note URL. If that note has an unresolved import, another import SHALL not create a replacement asset.

Explicit recovery in the original note SHALL insert the completed result once at the current cursor. It SHALL not copy or encode the image again. A running import SHALL remain pending. An import that actually failed SHALL allow a new source selection.

Navigation SHALL not discard a pending result or insert it into another note. No recovery path SHALL delete a referenced asset. Recovery of pending assets across relaunch remains part of the later image workflow.

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

### Requirement: Present edit recovery after dismissing source sheets

When a create-note sheet or vault picker requests navigation, that sheet SHALL dismiss before navigation begins. The root screen SHALL show the retain/discard decision directly from model state. It SHALL not depend on opening a second UIKit modal. Automatic dismissal SHALL not count as a user choice.

Dismissing a sheet without confirming a destination SHALL not navigate.

#### Scenario: A new-note action needs edit recovery

- WHEN the user confirms creation while the current note cannot be saved
- THEN the new-note sheet dismisses before the recovery decision is presented
- AND the requested name and destination folder are preserved until the decision completes

### Requirement: Recovery-copy actions remain independent

Deleting a retained copy SHALL only remove that copy. It SHALL not restore text, navigate to the original note, or start a provider save. Restore and Delete controls SHALL have independent hit targets in the recovery list.

#### Scenario: Delete after navigating away

- WHEN the user deletes a recovery copy while another note is selected
- THEN the selected note and its editor remain unchanged
- AND the recovery list remains open until explicitly dismissed

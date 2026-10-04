# image-loading Specification

## Purpose

Define asynchronous bounded image rendering, viewer loading and source import for partially downloaded provider-backed assets.

Status: planned; the associated change's unchecked tasks identify implementation and validation still required.

## ADDED Requirements

### Requirement: Render prepared images without synchronous source reads
The system SHALL asynchronously load and downsample image files with stable pending placeholders. Initial text construction, layout, viewer bodies and view creation/update SHALL perform no source-file read or decode. Successful results SHALL apply only to the current document/viewer generation.

#### Scenario: Pending image or dismissed viewer
- WHEN an image is unavailable, delayed, invalid or still decoding
- THEN text stays readable/scrollable, captions and stored markdown remain unchanged, and failed images expose retry
- AND the fullscreen viewer shows progress and permits immediate dismissal
- AND late results cannot reopen a dismissed viewer or alter another note
- AND supported formats, sizing/aspect ratio, zoom/pan, path containment and portable references remain supported without source migration

### Requirement: Bound image decode and cache memory
The system SHALL downsample from the source rather than first decoding full resolution, allow at most one active decode, cap inline images at 2048 pixels and viewer images at 4096 on the longest edge, and limit reusable decoded cache memory to 32 MiB.

#### Scenario: Large image or memory pressure
- WHEN a large source is loaded or a memory warning occurs
- THEN version/target-size cache keys avoid ordinary relayout rereads and duplicate requests are coalesced
- AND reusable images are evicted and optional queued work cancelled under memory pressure
- AND active viewer/transient memory is measured separately from the cache budget on an iPhone
- AND accessibility evidence reflects actual successful prepared-image load and visible bounds, without rereading the source

### Requirement: Import sources safely in background work
The system SHALL copy/encode Files/photo/camera sources into managed assets outside the main actor while retaining source/destination access for actual worker duration. It SHALL insert a portable relative reference only after successful import for the current document generation.

#### Scenario: Import fails, is cancelled, or finishes after navigation
- WHEN a source read, copy or encode cannot complete for the original note
- THEN editor text and insertion intent remain intact and the failed stage is recorded
- AND late import cannot insert into another note
- AND any unreferenced completed asset is handled without deleting assets referenced by saved or unsaved text
- AND save failure retains the imported reference/asset for retry; source removal and relaunch still render successfully saved assets

### Requirement: Validate image workflows on a device
The implementation SHALL include deterministic delayed/decode-failed/large-image, cache/memory, stale-viewer and import fault coverage and record physical-device Files/photo/camera and Dropbox acceptance before being declared validated.

#### Scenario: Device image acceptance
- WHEN insertion, scrolling, viewer loading/dismissal, cancellation, permission denial and save/reopen run on an iPhone
- THEN decoding and staging are absent from the main-thread trace, memory stays bounded, and original text/markdown/assets remain intact
- AND commit, device/iOS/provider/source details and evidence are recorded; absent required device evidence leaves validation pending

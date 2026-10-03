# Proposal

## Why

Flint hangs, freezes, and sometimes terminates on a physical iPhone when opening a Dropbox Files-provider vault with partially downloaded content. Current main-actor synchronous file access and image decoding can prevent even the loading screen from updating, while alerts alone provide no durable evidence of the failing stage or termination cause.

## What Changes

- Add structured local logging, correlated timings/signposts, slow-operation and responsiveness monitoring, bounded persistent breadcrumbs, and sanitized diagnostic export in Debug and Release.
- Collect available MetricKit crash/hang/performance evidence and document collection and symbolication of device crash, watchdog, and jetsam reports. Treat missing reports and interrupted launches as uncertain evidence.
- Move synchronous bookmark, coordination, discovery, preview, note, save, import, thumbnail, and viewer work off the main actor; bound concurrency, queues, caches, and decoded image size.
- Discover notes incrementally; load visible previews and selected-note content separately; render pending images without blocking text or layout.
- Add foreground loading deadlines, cancellation, safe retry, stale-result rejection, and recovery before repeating an interrupted automatic restoration.
- Preserve edit revisions, write ordering, access lifetimes, portable markdown, and assets across failure or cancellation.
- Require deterministic simulator faults and recorded physical-iPhone Dropbox performance/crash validation.

## Capabilities

### New Capabilities

- `runtime-diagnostics`: structured evidence, local telemetry, platform diagnostic collection, privacy, export, and interrupted-launch recovery. The new main spec was authored first to comply with AGENTS.md; it is explicitly labeled planned.
- `provider-file-access`: responsive bounded file access, incremental discovery, safe asynchronous editing, and lazy image decoding. The new main spec is likewise planned.

### Modified Capabilities

- `app-bootstrap`: bounded restoration, recovery presentation, and access scopes retained by cancelled workers until they stop.
- `note-management`: metadata discovery and initial note selection permit pending content rather than requiring every read before returning.
- `note-images`: asynchronous thumbnail/viewer loading preserves captions, markdown, and fallback behavior.
- `vault-management`: responsive progress, cancellation, and retries for provider-backed vaults.
- `testing-workflow`: physical-device validation for provider responsiveness and diagnostic evidence.

## Impact

Affected modules include `FlintApp`, `AppModel`, `VaultBookmarkStore`, `VaultFileService`, `RootView`, `VaultBrowserView` (picker staging, accessibility checks, and fullscreen image loading), `FlintMarkdownImageAttachment`, rich-text construction, and existing model/file/UI tests. File interfaces must support asynchronous operation identity, cancellation, revision-safe completion, and access leases; callers change together.

Use Apple's unified logging/signposts, MetricKit, and Image I/O with app-local diagnostic storage. No remote telemetry backend, automatic uploads, Dropbox SDK, custom native-crash recovery handler, or new external analytics dependency is included. Actual crash cause remains unconfirmed until device evidence is collected. Numeric budgets are initial acceptance limits to validate on the target iPhone, not measurements of the present app.

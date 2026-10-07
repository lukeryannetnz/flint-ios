# Design

## Context

See `proposal.md` for motivation. Inspection found:

- `AppModel` is `@MainActor`; its async entry points synchronously call bookmark and file modules. The async declaration does not move coordination or content reads to another executor.
- `VaultFileService.listMarkdownNotes` enumerates the whole tree, looks up dates, and reads the full contents of every markdown file to generate previews. `try?` hides optional failures. The existing coordinator helpers combine coordination wait and accessor work into one synchronous call.
- `FlintMarkdownImageAttachment` reads and renders the source at construction and layout. `NoteImageViewer` checks the filesystem in its SwiftUI body; `ZoomableImageView` loads full-resolution images in both creation and update. Picker staging and debug accessibility verification also contain synchronous reads/copies.
- No production logging, performance telemetry, durable launch journal, or platform diagnostic subscriber was found.
- Existing specs require initial content before vault opening returns and release previous security scopes before switching. The deltas explicitly revise those contracts for pending content and workers that outlive UI cancellation. Existing image portability, captions, formatting round trips, and source-selection flows remain required.

The reported termination might be a native crash, a watchdog kill due to main-thread blocking, or memory pressure from image decoding. Those are hypotheses; no device report was supplied.

## Goals / Non-Goals

**Goals:** Make slow provider activity observable and recoverable, isolate blocking work, and preserve document integrity while converting the callers to asynchronous operation lifecycles. Concentrate coordination, access lifetime, deadlines, and evidence behind small interfaces.

**Non-Goals:** A Dropbox SDK integration, background synchronization engine, remote analytics service, automatic uploads, custom signal handling, guaranteed capture of every OS termination, or continuing execution after a fatal native crash.

## Decisions

### 1. Introduce focused modules at existing seams

A diagnostics module owns event sanitization, operation intervals, bounded persistence, platform payload ingestion, launch markers, and export. Callers supply typed stage/outcome fields and operation identities; they do not assemble arbitrary dictionaries or write log files. A recording adapter exercises the same interface in deterministic tests.

An asynchronous vault-access module owns coordination, resource leases, bounded execution, discovery batches, content reads/writes, and import work. Replace the synchronous `VaultFileServing` interface and migrate its real and test adapters together. Use a dedicated bounded blocking executor rather than executing synchronous calls directly inside a Swift actor or launching an unlimited number of detached tasks. The main actor receives immutable results and publishes presentation state.

An image-loading module shares that file-access seam and owns Image I/O downsampling, generation-aware requests, and the decoded cache. UIKit views and attachments only render already prepared images/placeholders. Asset path validation, including symlink-escape checks, remains off the UI thread and continues to restrict images to the vault.

Alternative considered: add logging around the current synchronous calls. That helps attribution but still freezes UI and prevents recovery controls from running. Alternative considered: one Task per file. Blocking provider calls could exhaust cooperative execution resources or accumulate without limit.

### 2. Model logical cancellation separately from worker completion

Use a vault generation, document generation, operation UUID, and save revision. Each operation moves through queued, running, and one logical terminal outcome. On cancellation/timeout, close the user-visible interval, invalidate its generation, request `NSFileCoordinator.cancel()`, and keep an internal draining state until the accessor returns. Report late completion separately. Never use a structured task-group race that waits for its blocking child to terminate before returning the timeout.

Keep a reference-counted security-scope lease owned by the actual worker, including source-picker access and destination access during imports. UI switching relinquishes the UI lease but cannot invalidate active work. Start/stop access remain balanced. Create a coordinator per operation and propagate cancellation while waiting for coordination.

Executor limits are two active blocking jobs, one per vault, and 32 pending jobs. An old stuck vault therefore leaves one slot for a different vault. If both slots are stuck, return a recoverable busy state. Optional previews are lower priority than explicit reads and writes. Retry of a timed-out write waits for actual completion and establishes its outcome before writing again; a timeout is not proof that a write failed or rolled back.

Apple documents that cancellation does not stop an accessor already executing: [NSFileCoordinator.cancel](https://developer.apple.com/documentation/foundation/nsfilecoordinator/cancel()). This is why deadlines protect UI state, not a claim that OS-level I/O has ceased.

### 3. Split discovery, previews, and selected content

Enumerate metadata incrementally, publish coalesced bounded batches, and maintain a stable identity per note URL in app state. Avoid eager content reads during discovery. Request preview prefixes only for visible/recent cards; cap source bytes at 64 KiB, handle split UTF-8 boundaries, and cap cached previews at 4 MiB. Preserve metadata sort rules as later batches arrive; do not repeatedly auto-select as ordering changes. A partial failure keeps the discovered list and exposes incomplete discovery rather than showing an empty-vault success.

Enumeration jobs yield their vault's worker slot between batches so explicit note reads and saves can take priority; a single long-lived enumeration job must not monopolize that slot after publishing initial metadata. An individual provider call may still block a batch, in which case the deadline and cancellation rules apply.

Selected content loads separately with a 30-second foreground deadline and an 8 MiB source-byte cap enforced during reading. Oversized or incomplete reads never produce editable partial documents. Prepare Foundation-only markdown work off the main actor where safe; apply UIKit-dependent attributed presentation on the main actor in bounded updates without filesystem access. Profile that remaining formatting work to ensure large accepted notes do not create a new unbounded UI stall.

Save snapshots capture text, revision, URL, and lease. Completion for an older revision does not clear newer edits. Before navigation, persist pending edits or obtain an explicit retain/discard decision; a retained recovery copy belongs in separate protected app-local document-recovery storage, never in diagnostics. Its retention and retry UI must make the original destination clear. Writes remain coordinated and atomic where supported, and independent metadata refresh cannot turn a successful write into a failed-save claim.

### 4. Downsample images and eliminate reads from rendering

Use Image I/O thumbnail creation with decode caching disabled for the full source and a target pixel size derived from layout/display scale. Inline requests cap the longest edge at 2048 pixels, viewers at 4096; the cache holds at most 32 MiB of decoded images, and only one decode is active. The active viewer can require up to approximately 64 MiB for a 4096-square RGBA image outside the reusable cache; measure transient memory on the device rather than treating the cache limit as a total process-memory limit.

Cache by resource/version and size. Layout changes request an appropriate cached size and never reopen a source synchronously. Deduplicate concurrent requests, cancel optional requests for offscreen content, and evict cache entries on memory warning. Missing/provider-pending/decode-failed images preserve text and captions. The viewer receives prepared images and can dismiss immediately while work drains. Replace accessibility verification that rereads sources with actual prepared-load state; tests must still assert rendered bounds and successful decode.

Move Files/photo picker staging copies and camera encoding to background work while retaining the source access lease. Preserve real source callbacks and the managed-asset-before-reference insertion ordering. Late imports cannot insert into a different document; cleanup cannot remove an asset referenced by saved or unsaved markdown.

### 5. Use unified logging plus a local sanitized journal

Use `Logger` with subsystem `com.lukeryan.flint` and categories for launch, bookmarks, provider coordination, discovery, notes, images, saves, lifecycle, and diagnostics. Use signpost intervals for stage profiling. Opaque operation/resource identifiers, numeric counts, safe error domains/codes, and explicit stage names are public; private content is omitted from the journal rather than relying only on log redaction. Never traverse error `userInfo` unrestrictedly.

Persist a versioned JSON-lines journal, compact launch marker, and sanitized platform reports in Application Support outside any provider-backed vault, protected after first device unlock and excluded from backup. Use a dedicated writer and a bounded event queue (initially 512 events, maximum 16 KiB per ordinary event). Limit the aggregate journal/report store to 20 MiB and 7 days, deleting oldest records first. Prefer terminal/error events under queue pressure but never block application operations. Incomplete trailing records are recoverable. Track dropped/truncated counts without recursive logging.

Write operation-start breadcrumbs before dispatching provider work; retain terminal records and occasional coalesced stage progress. The restoration safety marker must be committed before provider access, but marker persistence must itself have a bounded wait. If it cannot be persisted, show recovery and require explicit opening rather than automatically restoring without crash-loop protection. Graceful backgrounding/termination markers improve context but cannot guarantee that every normal termination is observable.

Local performance telemetry is the default for this proposal. Users explicitly export/share; no network uploader or SDK is introduced. The export contains only bounded app-local evidence, available platform reports, build/device/OS data, and collection limitations. Generate at most one 20 MiB temporary export at a time and remove it after sharing/cancellation or on next startup, so export staging does not grow without bound. Preview the categories and time range and support clearing history without clearing bookmarks or document-recovery copies.

Apple references: [Logging](https://developer.apple.com/documentation/os/logging), [OSLogPrivacy](https://developer.apple.com/documentation/os/oslogprivacy).

### 6. Collect independent hang and crash evidence

Register a process-lifetime MetricKit subscriber before restoration. Persist sanitized `MXMetricPayload` and `MXDiagnosticPayload` off the main actor; allowlist diagnostic types, timestamps, build/binary UUIDs, call stacks, durations, and aggregate metrics. Deduplicate by canonical sanitized payload identity. Receipt time is not crash time; only correlate an operation when diagnostic timestamps and build evidence support it, otherwise record an unknown correlation.

A small independent responsiveness monitor checks a main-thread heartbeat, records foreground gaps of at least 2 seconds and active-operation context, and emits recovery duration. Its thread-safe snapshot must not call back into a blocked main actor or vault executor. Suspend monitoring and deadline accumulation while the app is not foreground-active. These observations identify suspected hangs; platform reports establish richer crash/hang evidence when available. The monitor must not enumerate stacks or create a busy polling loop.

An unfinished restoration marker on next launch shows recovery before provider access. An unfinished generic session marker is only an unclean-session observation: force quitting and other OS exits can produce it. Do not suppress native crashes, install Swift signal recovery, or claim all crashes/watchdog/jetsam reports are delivered by MetricKit. Retain binary UUID-matching archives/dSYMs and document Xcode device/Organizer collection for missing platform evidence.

Apple references: [MXMetricManager](https://developer.apple.com/documentation/metrickit/mxmetricmanager), [MXDiagnosticPayload](https://developer.apple.com/documentation/metrickit/mxdiagnosticpayload), [MetricKit diagnostic overview](https://developer.apple.com/videos/play/wwdc2020/10081/), [Identifying common crash causes](https://developer.apple.com/documentation/xcode/identifying-the-cause-of-common-crashes).

## Risks / Trade-offs

- A provider accessor may never return → Logical deadlines and bounded workers preserve recovery; eventual system termination may still be necessary when both slots remain blocked. This limitation is shown honestly rather than spawning more workers.
- Provider availability metadata varies → Treat unavailable observations as unknown and diagnose actual coordination/read outcomes. Do not use iCloud-only keys as a universal download-state check.
- Incremental discovery changes ordering and initial selection timing → Preserve existing sort criteria and select once per generation; tests cover user selection during later batches.
- Async writes can finish after cancellation → Serialize per note, retain original destination leases, keep dirty text, and expose uncertain outcomes before retry.
- Diagnostics may be missing after a hard termination → Persist early breadcrumbs, collect platform/device reports, and retain symbols; do not claim a launch marker proves a crash.
- Diagnostic records or platform reports may contain sensitive paths → Typed allowlists, launch-scoped identifiers, sanitizer fixtures, and explicit user export.
- Logs and image caches add disk/memory pressure → Enforce stated budgets, degrade gracefully, and validate with large images on the target phone.
- The 8 MiB editable-note limit changes behavior for large notes → Present a clear recoverable size-limit error without altering the file; document this limit before release.

## Migration Plan

1. Capture a physical-device baseline with an identified fixture, an Instruments trace, and available termination reports. Record unknowns rather than blocking simulator fault development on a missing report.
2. Build diagnostics and early launch markers first, then replace synchronous file interfaces and migrate all callers/tests together.
3. Introduce incremental discovery, revision-safe saves, lazy previews, and asynchronous image loading; retain existing markdown and image workflow coverage.
4. Run the full required simulator suite. Record physical-device Dropbox validation, source-adapter checks, privacy export review, and symbolication evidence before calling the implementation validated.
5. Keep bookmarks and vault files compatible; version app-local journals so unsupported old data is ignored safely. Rollback must preserve bookmarks, source notes, referenced assets, and retained document-recovery copies. Never roll back by changing the vault format or discarding unsaved edits.

## Open Questions

- Which platform report explains the reported hard termination? Answer from the physical-device baseline; the design collects evidence for native crashes, watchdog exits, and memory pressure without depending on one diagnosis.
- What are the target vault size, image dimensions, device model, and iOS/Dropbox versions? Record these during device validation; acceptance budgets above remain the contract unless revised explicitly before implementation.

## Phase 2 implementation decisions

Reuse DebugLog's app-local writer and aggregate retention for sanitized `.report` records. MetricKit conversion runs on that writer, behind an eight-delivery admission limit; canonical report hashes deduplicate independently of receipt time. Preserve numeric aggregate measurements and UUID/address/offset/sample stack fields while omitting binary names and exception text. Correlation remains unknown until later operation/build-window matching exists.

RestorationSafety owns a separate one-second-bounded writer and a protected atomic marker. Explicit retry replaces an unfinished marker; failed or late safety writes never authorize automatic provider work. Bootstrap's recovery presentation preserves bookmarks, with sharing added by phase 6. Provider execution remains synchronous until phase 3.

ResponsivenessMonitor uses an independent utility timer with a thread-safe action registry and one outstanding main-queue acknowledgment. Controlled clocks test thresholds and inactive intervals. Slow observations include the last completed child step; suspected-stall observations include up to 32 active IDs and the total count. These remain suspected responsiveness observations, never crash diagnoses.

## Phase 3 implementation decisions

ProviderExecutor owns worker slots and source/destination leases independently of logical UI completion. Shared attempts carry foreground budgets and retain actual mutation outcomes for safe retries. AppModel uses vault/document/navigation generations, revision snapshots and serialized saves; late results cannot publish stale state. Programmatic browser selection does not trigger duplicate navigation. See `docs/provider-access.md` for guarantees and fault coverage. A minimal bounded app-local recovery snapshot satisfies phase 3 recovery; preview/time selection and clear-history remain phase 6. Eager previews, inline/viewer source reads and picker staging retain their planned phase 4/5 scope.

Phase 3 review refinement: mutation values distinguish created URLs, full `InsertedNoteImage` results and valueless saves. AppModel retains pending image outcomes by original note URL, including successful imports whose caller became stale. Explicit Recover image at cursor consumes a completed outcome once; pending outcomes block replacement imports for that note. No image is inserted automatically after timeout or into another note. This process-local recovery does not claim durable reconciliation after relaunch, and it does not delete referenced assets.

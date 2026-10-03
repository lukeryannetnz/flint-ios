# Tasks

## 1. Baseline evidence and diagnostic foundation

- [ ] 1.1 Record a physical-iPhone baseline using a partially downloaded Dropbox fixture: build, device/iOS/provider versions, note/image sizes, network state, loading timing, Instruments main-thread trace, and available crash/watchdog/jetsam reports; verify the delivered baseline distinguishes observed evidence from suspected causes.
- [ ] 1.2 Add the typed diagnostics interface, unified logging categories, correlation identities, monotonic timings, and signposts; verify recording-adapter tests cover stage hierarchy, success/error/cancel/timeout outcomes, and exactly one logical terminal event.
- [ ] 1.3 Add allowlisted error/platform-field sanitization and launch-scoped resource identifiers; verify fixtures containing filenames, URLs, text, alt text, bookmarks, credentials, and nested errors do not appear in persisted or exported records.
- [ ] 1.4 Add protected app-local journal/marker storage, bounded queue, record-size limits, rotation, and corrupt-tail recovery; verify disk-full, queue saturation, over-limit payload, expiry, and relaunch tests without provider access or main-thread writes.
- [ ] 1.5 Document diagnostic event fields, thresholds, retention, redaction, and device log/signpost collection; verify a sample sanitized launch trace is interpretable with the documented procedure.

## 2. Platform evidence and restoration safety

- [ ] 2.1 Register the process-lifetime MetricKit subscriber before bootstrap, ingest sanitized metrics and diagnostic payloads, and deduplicate deliveries; verify synthetic old-build/old-time payloads are not attributed to the receiving launch.
- [ ] 2.2 Add durable restoration-start/completion/abandonment markers and early recovery after an unfinished restoration; verify relaunch and failed-marker-write tests enter recovery before provider work without deleting bookmarks.
- [ ] 2.3 Add independent foreground slow-operation and heartbeat monitoring with a controlled clock; verify 5-second operation and 2-second responsiveness thresholds, bounded event volume, recovery durations, and exclusion of background suspension.
- [ ] 2.4 Document symbol-file retention and Xcode device/Organizer crash, watchdog, and jetsam collection; verify one available or simulated report can be matched to the intended build and document missing evidence honestly.

## 3. Asynchronous file access and worker lifetime

- [ ] 3.1 Replace the synchronous vault-file interface with asynchronous operation results and migrate `AppModel`, bookmark restoration, real adapters, and spies; verify ordinary vault creation, open, note creation/read/write, and existing import tests through the new interface.
- [ ] 3.2 Add the bounded blocking executor with two global slots, one per vault, 32 pending requests, priority for explicit actions, and a separately bounded decode lane; verify fault tests prove concurrency/queue limits and no provider access executes on the main thread.
- [ ] 3.3 Add per-operation coordination cancellation, generation invalidation, 30-second foreground deadlines, and independent logical completion; verify blocked-before-accessor and blocked-inside-accessor tests return UI recovery without waiting and reject late results.
- [ ] 3.4 Add worker-owned source/destination security-scope leases; verify timed-out workers retain access until actual completion, start/stop calls balance, and another vault can use the remaining slot.
- [ ] 3.5 Integrate explicit loading/pending/recovery state into `AppModel` and `RootView`, including retry saturation and uncertain creation outcomes; verify UI fault cases can cancel, choose another vault, or export without stale alerts/state replacing the current screen.
- [ ] 3.6 Document cancellation guarantees, worker capacity, and lease lifetime in the module interface; verify tests demonstrate the documented distinction between logical cancellation and actual accessor termination.

## 4. Incremental note loading and safe persistence

- [ ] 4.1 Split metadata enumeration from content loading, publish bounded/coalesced batches, and preserve sort and regular-file filtering rules; verify partial-enumeration and unavailable-item tests keep discovered notes visible and never misreport an incomplete vault as empty.
- [ ] 4.2 Add demand-driven previews with a 64 KiB source limit, UTF-8 boundary handling, and a 4 MiB cache; verify visible-note demand, truncated/unavailable/empty states, cache invalidation, and no eager whole-vault content reads.
- [ ] 4.3 Load selected notes with generation checking and the 8 MiB enforced read limit; verify pending first-note state, selecting a different note, missing metadata, growing oversized files, failed reads, and no editable partial document or unintended write.
- [ ] 4.4 Capture revision-safe save snapshots and serialize writes per note; verify editing during a save preserves newer dirty text, failure retains edits, uncertain timed-out writes do not overlap retries, and metadata-refresh errors do not report a completed write as failed.
- [ ] 4.5 Add save-before-navigation and explicit retain/discard recovery choices with protected document-recovery storage separate from diagnostics; verify destination identity and retained-text integrity across note/vault switching and relaunch.
- [ ] 4.6 Update note-list/editor loading presentation and document the large-note limit, incomplete discovery, and edit-recovery behavior; verify existing markdown round trips and folder/recent sorting tests still pass.

## 5. Lazy image loading and authoring

- [ ] 5.1 Add coordinated asynchronous image loading and Image I/O downsampling with 2048/4096-pixel limits, one active decode, and a 32 MiB decoded cache; verify large-image, decode failure, cache eviction, deduplication, and memory-warning tests.
- [ ] 5.2 Replace attachment construction/layout source reads with prepared-image state and stable placeholders; verify note text appears before delayed images, captions and stored markdown are unchanged, and ordinary relayout does not reread the source.
- [ ] 5.3 Replace viewer body/create/update filesystem work with generation-aware prepared images; verify dismissal during blocked loading is immediate and late completion cannot reopen the viewer.
- [ ] 5.4 Move Files/photo staging copies, image imports, and camera encoding off the main actor while retaining access leases and managed-asset ordering; verify source failure/cancellation, stale document completion, and referenced-asset preservation tests through real callback paths.
- [ ] 5.5 Replace debug accessibility checks that synchronously reread image files with actual prepared-load state; verify existing image UI tests still assert successful loading, visible bounds, insertion position, portability, save/reopen, and failed-save retry.
- [ ] 5.6 Document loading/retry and image-memory behavior and source-adapter changes; verify physical-device Files/photo/camera permission, cancellation, insertion, and save/reopen outcomes required by the existing testing workflow are recorded.

## 6. Diagnostic export and recovery usability

- [ ] 6.1 Add Export diagnostics to onboarding, loading recovery, and ready state with category/time-range preview and system sharing; verify export during a blocked provider uses only app-local evidence and excludes private document data.
- [ ] 6.2 Add bounded one-at-a-time export staging, cleanup, clear-history, and graceful export failure; verify bundles identify missing/dropped evidence, cleanup survives relaunch, and clearing preserves bookmarks, document recovery, and a minimal launch-safety marker.
- [ ] 6.3 Document the reproduction/export procedure and local-only telemetry behavior; verify the documented steps produce an interpretable sanitized bundle on the test iPhone.

## 7. Integration acceptance

- [ ] 7.1 Run the complete AGENTS.md simulator command on iPhone 17 or another available iOS Simulator and record the result; verify all model/file/UI suites and deterministic provider/diagnostic fault cases run, explaining and resolving failures rather than relying on an unexplained passing retry.
- [ ] 7.2 Complete the physical-iPhone Dropbox matrix for downloaded, pending, unavailable, large, and invalid note/image fixtures online, offline, during download, and after interrupted restoration; verify responsiveness, deadlines, bounded memory/work, safe retry, export, and markdown/asset integrity against both new specs.
- [ ] 7.3 Deliver a validation record with commit/build identity, fixture conditions, before/after timings, Instruments trace, sanitized export, available symbolicated crash/hang evidence or explicit absence, and remaining limitations; keep the change awaiting device validation if the required device setup is unavailable.
- [ ] 7.4 Verify implementation against every proposal delta, then reconcile main specs and archive only after required checks pass; verify no planned requirement is mislabeled as implemented and no conflicting bootstrap or selection contract remains.

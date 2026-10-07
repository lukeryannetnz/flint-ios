# Tasks

## 1. Baseline evidence and diagnostic foundation

- [ ] 1.1 Record a physical-iPhone baseline using a partially downloaded Dropbox fixture: build, device/iOS/provider versions, note/image sizes, network state, loading timing, Instruments main-thread trace, and available crash/watchdog/jetsam reports; verify the delivered baseline distinguishes observed evidence from suspected causes.
- [ ] 1.2 Add the typed diagnostics interface, unified logging categories, correlation identities, monotonic timings, and signposts; verify recording-adapter tests cover stage hierarchy, success/error/cancel/timeout outcomes, and exactly one logical terminal event.
- [ ] 1.3 Add allowlisted error/platform-field sanitization and launch-scoped resource identifiers; verify fixtures containing filenames, URLs, text, alt text, bookmarks, credentials, and nested errors do not appear in persisted or exported records.
- [ ] 1.4 Add protected app-local journal/marker storage, bounded queue, record-size limits, rotation, and corrupt-tail recovery; verify disk-full, queue saturation, over-limit payload, expiry, and relaunch tests without provider access or main-thread writes.
- [ ] 1.5 Document diagnostic event fields, thresholds, retention, redaction, and device log/signpost collection; verify a sample sanitized launch trace is interpretable with the documented procedure.

## 2. Platform evidence and restoration safety

- [x] 2.1 Register the process-lifetime MetricKit subscriber before bootstrap, ingest sanitized metrics and diagnostic payloads, and deduplicate deliveries; verify synthetic old-build/old-time payloads are not attributed to the receiving launch.
- [x] 2.2 Add durable restoration-start/completion/abandonment markers and early recovery after an unfinished restoration; verify relaunch and failed-marker-write tests enter recovery before provider work without deleting bookmarks.
- [x] 2.3 Add independent foreground slow-operation and heartbeat monitoring with a controlled clock; verify 5-second operation and 2-second responsiveness thresholds, bounded event volume, recovery durations, and exclusion of background suspension.
- [x] 2.4 Document symbol-file retention and Xcode device/Organizer crash, watchdog, and jetsam collection; verify one available or simulated report can be matched to the intended build and document missing evidence honestly.

## 3. Asynchronous file access and worker lifetime

- [x] 3.1 Replace the synchronous vault-file interface with asynchronous operation results and migrate `AppModel`, bookmark restoration, real adapters, and spies; verify ordinary vault creation, open, note creation/read/write, and existing import tests through the new interface.
- [x] 3.2 Add the bounded blocking executor with two global slots, one per vault, 32 pending requests, priority for explicit actions, and a separately bounded decode lane; verify fault tests prove concurrency/queue limits and no provider access executes on the main thread.
- [x] 3.3 Add per-operation coordination cancellation, generation invalidation, 30-second foreground deadlines, and independent logical completion; verify blocked-before-accessor and blocked-inside-accessor tests return UI recovery without waiting and reject late results.
- [x] 3.4 Add worker-owned source/destination security-scope leases; verify timed-out workers retain access until actual completion, start/stop calls balance, and another vault can use the remaining slot.
- [x] 3.5 Integrate explicit loading/pending/recovery state into `AppModel` and `RootView`, including retry saturation and uncertain creation outcomes; verify UI fault cases can cancel, choose another vault, or export without stale alerts/state replacing the current screen.
- [x] 3.6 Document cancellation guarantees, worker capacity, and lease lifetime in the module interface; verify tests demonstrate the documented distinction between logical cancellation and actual accessor termination.

## 4. Incremental note loading and safe persistence

- [x] 4.1 Split metadata enumeration from content loading, publish bounded/coalesced batches, and preserve sort and regular-file filtering rules; verify partial-enumeration and unavailable-item tests keep discovered notes visible and never misreport an incomplete vault as empty.
- [x] 4.2 Add demand-driven previews with a 64 KiB source limit, UTF-8 boundary handling, and a 4 MiB cache; verify visible-note demand, truncated/unavailable/empty states, cache invalidation, and no eager whole-vault content reads.
- [x] 4.3 Load selected notes with generation checking and the 8 MiB enforced read limit; verify pending first-note state, selecting a different note, missing metadata, growing oversized files, failed reads, and no editable partial document or unintended write.
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

## Phase 2 validation — 2026-10-06

- Implemented tasks 2.1–2.4: process-lifetime MetricKit collection before bootstrap; sanitized deduplicated app-local reports; bounded restoration safety and recovery; independent foreground operation/heartbeat monitoring; and device-report/symbol collection documentation.
- Full required AGENTS.md iPhone 17 simulator suite on iOS 26.5: **66 passed, 0 failed, 0 skipped**. Result: `/tmp/flint-derived-data/Logs/Test/Test-Flint-2026.10.06_19-59-56-+1300.xcresult`; command log: `/tmp/flint-runtime-phase2-tests.txt`.
- New coverage includes delayed old-build reports, private payload fields, stack/depth bounds, deduplication, queue saturation, shared report/journal retention, unfinished/corrupt/unwritable markers, bounded marker waits and retries, explicit restoration retry, abandonment on choosing another vault, foreground thresholds, suspension and stale heartbeat exclusion.
- Build identity: version 1.0/build 1; base commit `dc3da15` plus this working-tree change. Final simulator debug dylib and generated `/tmp/flint-phase2-final-symbols.dSYM` both report arm64 UUID `9D2853AE-A8A1-3B80-BEB4-C0406939EAAA`. The documented matching exercise uses a simulated frame, not a collected crash.
- Earlier attempts: sandbox CoreSimulator access failed; reran with approved access. Compilation exposed an unavailable `MXDiskWriteExceptionDiagnostic.totalSampledTime` property; corrected ingestion to preserve only its actual byte measurement. A first complete run passed 63 tests; subsequent runs included additional edge-case tests and final writer/stack refinements. The final full run passed after those changes. No failing test was accepted on an unexplained retry.
- Strict OpenSpec validation and `git diff --check`: passed.
- Physical-iPhone Dropbox fixtures, performance traces, actual MetricKit delivery, crash/watchdog/jetsam reports and release archive symbol matching remain pending. Provider calls still execute synchronously until phase 3; phase 6 supplies diagnostic sharing. This change remains awaiting device validation and is not archived.
- Earlier foundation tasks remain unchecked where their broader requirements (including baseline evidence, marker integration, category/error-chain completeness and device collection) are not fully demonstrated by the prior diagnostic-journal work. Completion of this phase does not mark all runtime-diagnostics requirements implemented.

## Phase 3 validation — 2026-10-08

- Tasks 3.1–3.6 complete (10/34 overall): async vault/bookmark adapters, two global/one-per-root workers, 32 pending requests, explicit priority, one decode lane, foreground deadlines, logical cancellation independent of actual termination, worker-owned leases and recovery UI. See `docs/provider-access.md`.
- Final AGENTS.md iPhone 17/iOS 26.5 suite: **98 passed, 0 failed, 0 skipped**. Result: `/tmp/flint-derived-data/Logs/Test/Test-Flint-2026.10.08_07-05-45-+1300.xcresult`; log: `/tmp/flint-pr25-navigation-full.txt`. Release simulator build passed in `/tmp/flint-pr25-image-release.txt`. Strict OpenSpec validation and whitespace checks passed.
- Build identity: app version 1.0/build 1, base `f9ad36a` plus retention before stale navigation rejection; final commit and hosted CI result are recorded in PR #25.
- Coverage includes blocked coordination/accessors/scope acquisition, retained scopes/slots, saturation/priorities, background budget exclusion, stale vault/note/export/safety results, revision-safe saves, uncertain creations, successful creation followed by discovery/read failure, valid bookmark followed by corrupt content, and typed file/camera late outcomes recovered once in the original note without another asset mutation, overlapping source callback rejection, new-source admission after actual late failure, and creation retry after concurrent navigation.
- Original hosted CI compiled successfully but failed a three-second cleanup poll in the two-draining-workers test. Tests now await actual scope/slot-release notification with a bounded harness wait; controlled foreground deadlines remain unchanged. CI runs simulator test runners serially. Hosted CI on `f9ad36a` passed (run 37592339875); final creation-retention CI is tracked in PR #25.
- A local run used a stale UI binary (old `test.retry-save` selector, omitted folder test). Its failure was explained by comparing the runner to current source, then cleaning derived products. The final clean run compiled the current UI tests and passed both cases; no unexplained passing retry was accepted. Added regression failures were observed before applying each fix.
- Image-outcome recovery is process-local and explicit at the current cursor. Incremental previews/large-note limits, prepared image loading/picker staging, full diagnostic preview/clear-history and physical-iPhone Dropbox/Instruments acceptance remain future phases. The change is not archived.

## Phase 4 note loading validation — 2026-10-08

- Tasks 4.1–4.3 complete (13/34 overall): metadata-only batches, worker release between batches, partial/incomplete discovery and retry, demand-driven preview prefixes/cache, usable browser before initial content, and enforced bounded selected-note reads. Save snapshot/order protections from phase 3 remain; tasks 4.4–4.6 await their remaining durable edit-recovery behavior and reconciliation.
- Full AGENTS.md iPhone 17/iOS 26.5 suite: **120 passed, 0 failed, 0 skipped**. Result: `/tmp/flint-derived-data/Logs/Test/Test-Flint-2026.10.08_09-16-50-+1300.xcresult`; log: `/tmp/flint-phase4-final-admission.txt`. Release simulator build passed: `/tmp/flint-phase4-final-release.txt`. Strict OpenSpec validation and whitespace checks passed.
- Build identity: version 1.0/build 1; new worktree branch `codex/provider-note-loading-phase-4` based on phase 3 commit `2cfdb1a`. Final commit, stacked MR and hosted CI run are recorded in the MR.
- Fault coverage proves metadata enumeration never decodes content, batches stay within 64 notes/256 entries, workers release between batches, unavailable/unknown regular-file metadata marks incomplete discovery, partial results survive failure, and late batches cannot replace another vault. Initial pending content, newer user selection, and delayed restoration-safety completion are generation guarded.
- Preview coverage checks no eager demand, optional priority, deduplication, offscreen cancellation, unavailable/empty/truncated states, 64 KiB actual source budget, valid split UTF-8 handling, invalid-byte rejection, LRU budget eviction, source-version invalidation, successful-save invalidation and explicit refresh. Visible rows renew demand after invalidation.
- Editable-read coverage checks exact 8 MiB acceptance, actual byte enforcement without metadata, simulated growth and interrupted reads, invalid UTF-8, unchanged oversized files, no placeholder writes, and retry. A real-adapter UI case verifies an oversized note presents the limit error and another note can still open. Existing markdown round trips, folder/recent sorting and image UI workflows pass.
- The first focused run identified the placeholder edit guard and two changed-fixture assumptions (bookmark refresh at usable metadata, and initial sorting); these were corrected explicitly. Subsequent full runs passed, and the final suite includes visible-demand renewal and restoration-boundary race refinements. No unexplained passing retry was accepted.
- Physical-iPhone Dropbox/Instruments acceptance remains pending. Image reads in rendering/picker staging, durable document recovery and full diagnostic preview/clear-history remain later work. This change is not archived and does not claim the physical-device failure is resolved.

- MR #26 review regressions reproduced before fixes: an older cursor could prune a newly created note after a newer full listing, and an exact 64 KiB source was labelled truncated. Complete creation/save listings now invalidate older discovery before publication, and coordinated end-offset checks identify EOF without reading beyond the source budget. Both new regressions and the final full suite pass.

- A further review regression reproduced stale selection after an externally removed note. Explicit discovery refresh now reconciles an unchanged clean selection after complete discovery, opens the first remaining note or clears an empty editor, retains dirty missing-destination text with an error, and cannot override selection changed while metadata awaited. Full simulator/Release verification passes after this refinement.

- Final review regressions reproduced optional discovery admission during delayed restoration safety and stale preview/metadata after confirmed late save success. Initial content now completes logically before automatic discovery/previews are admitted; metadata generations reject superseded deferred cursors and visible demand renews when the gate opens. Confirmed late saves invalidate previews and use the shared metadata finalizer with a fresh bounded attempt inside the save-task lifecycle. Actual worker cleanup notifications and controlled clocks verify this without another write. The final full suite and Release build pass.

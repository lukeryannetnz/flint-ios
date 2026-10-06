# Reading Flint's debug logs

Flint records a local debug log in development and release builds. It starts before saved-vault restoration. The log records actions rather than note content: no filenames, folder paths, note text, image captions, bookmark data, account information, or error descriptions are submitted.

## Saved entries

The app's `Library/Application Support/DebugLogs` folder contains JSON-lines segments, excluded from backup and protected until the device has been unlocked once after restart. Disk access uses a utility queue, never the screen-update thread or a file-provider worker. Logs retain at most 20 MiB for seven days; pruning runs on writes, snapshots, startup, and hourly while the app is running. Suspension can delay maintenance until the app runs again.

Each line has these fixed fields:

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Log format, currently 1 |
| `timestamp` | UTC event time |
| `elapsedSeconds` | Time since logger initialization using the monotonic system clock |
| `severity` | `info` or `error` |
| `step`, `result` | Fixed vocabulary for the action and its outcome |
| `appVersion`, `build`, `launchID` | App and launch identity |
| `actionID`, `parentActionID` | Link related steps without document names |
| `fileID` | A keyed identifier that changes each launch; the URL is never saved |
| `durationSeconds`, `count`, `bytes` | Optional duration, number of files/events, and bytes |
| `errorCategory`, `errorCode` | Fixed error category and permitted Cocoa error codes; step context distinguishes corrupt bookmarks, coordination and image failures. Explicit platform codes distinguish unavailable downloads from unavailable providers; other errors are `unknown` |

`started` is followed by one final result: `success`, `failure`, `cancellation`, `timeout`, or `abandonment`. A timed-out/cancelled action that later finishes records one `finishedLater` observation. A hard process termination can leave only a start entry; that alone does not establish a crash cause. For `securityScope`, `count=1` means iOS started scoped access; `count=0` means it did not start, which does not by itself prove permission denial (app-owned files may not need it).

`droppedEntries` counts events lost to queue or storage limits when the writer can next save them. Accumulated counts are cleared only after the counter entry is successfully saved, so repeated storage failures preserve the count. Loss counters are in memory and can themselves be lost if the process exits.

For example, entries with one parent action might show:

```text
vaultOpen          started
  coordinationRead started
  coordinationRead success       durationSeconds=12.4
  fileRead         started
    preview        failure       errorCategory=permission errorCode=257
  fileRead         success
vaultOpen          success
```

This says coordination took 12.4 seconds and one preview failed permission checking, while the overall action returned successfully using a fallback. An unfinished `coordinationRead` indicates where waiting began; it does not identify which provider or claim a download state.

## Console and Instruments

Connect the iPhone to the Mac, select it in Console, and filter subsystem `com.lukeryan.flint`, category `DebugLog`. Apple log output contains only step, result and action ID. For timing, record the app with Instruments' Points of Interest instrument and inspect `Flint action` intervals. Their fixed step labels and action IDs match saved records. Disk writing happens on `flint.debug-log`.

JSON lines can be inspected from an app container obtained through Xcode's Devices and Simulators window. Incomplete/malformed entries are skipped by the snapshot API; snapshots also re-encode only permitted fields and apply retention limits. User-facing sharing and crash-report collection belong to the recovery feature.

## API for the recovery implementation

`DebugLog.shared` is initialized by launch instrumentation. Call `begin(_:file:parent:)` for a retained `DebugLogAction`; finish it with a typed result and optional error/count/bytes. Repeated final results are ignored, except one late completion after timeout/cancellation. `measure` wraps synchronous throwing work and propagates a task-local parent action. `measureAsync` wraps app-model actions; `handledFailure` records errors caught inside them. Do not pass document contents anywhere.

`snapshot(completion:)` returns complete sanitized JSON lines asynchronously on the log writer queue. The caller must dispatch UI updates to the main actor. It never reads the vault. This method gives the recovery feature saved log data without coupling it to file services; the recovery feature owns its export UI and platform reports.

File operations remain synchronous in this change. Moving provider access off the screen-update thread and adding actual deadlines belongs to the background file-loading spec. The logger supports timeout/late-completion events but does not impose those deadlines itself.

## Platform evidence and restoration safety

MetricKit is registered for the process before bootstrap in Debug and Release. Deliveries are converted on `flint.debug-log`; at most eight deliveries wait. `.report` files share the journal's 20 MiB/seven-day budget. SHA-256 of canonical sanitized content deduplicates reports across launches; receipt time is stored separately. `platformSnapshot` returns sanitized app-local reports asynchronously.

Reports contain original window start/end, numeric app version/build when available, report kind, finite numeric metrics, and bounded UUID/address/offset/sample stack frames with thread index, attributed-thread flag and tree depth. Binary names, exception messages, signpost strings and unrestricted metadata are omitted. Metrics include CPU seconds, foreground seconds, peak memory bytes and logical disk-write bytes when delivered. Stack collection is limited to 64 stacks, 1,024 frames and 33 levels; truncation is explicit. Current-launch attribution is always `unknown`. A later delivery can describe an older build; never join it to current operations based on receipt time.

The independent `flint.responsiveness` timer samples every 250 ms, with at most one main-queue heartbeat pending. It emits one slow observation after five foreground seconds per action, a suspected heartbeat stall at two seconds, and a recovery duration when acknowledged. Background/inactive time is excluded. `observedStep` identifies the last completed child step for slow observations; `relatedActionIDs` contains up to 32 active IDs at a stall, with `count` giving the total. This evidence does not prove a crash.

`Library/Application Support/RestorationSafety/marker.json` is protected and excluded from backup. Its schema version, launch/action IDs, timestamp and started/completed/abandoned state contain no vault identity. Bootstrap checks and commits it before bookmark resolution; a one-second failure/timeout or unfinished/corrupt marker shows recovery. Retry is explicit; choosing another vault marks the previous restoration abandoned and retains the saved selection until the user replaces it. Handled success/failure commits completion/abandonment. Late safety writes do not start provider work, and one occupied safety writer rejects repeated requests rather than accumulating work. Provider operations now use the bounded asynchronous executor described in [provider-access.md](provider-access.md). Recovery offers a minimal local snapshot; category/time preview and clear-history controls remain pending phase 6.

## Collecting crash, watchdog and jetsam evidence

For each distributed build, retain the `.xcarchive`, app binaries and matching dSYMs with commit, app version/build, architecture and binary UUIDs. In Xcode Organizer, choose the archive and retain/export its symbols; keep these for the lifetime of supported builds. Use `dwarfdump --uuid <binary>` and `dwarfdump --uuid <dSYM>/Contents/Resources/DWARF/<binary-name>` and require matching UUID **and architecture** before symbolication. A matching marketing version alone is insufficient. For Debug builds with a debug dylib, retain that dylib and its corresponding symbols too.

Connect the iPhone, open Xcode → Window → Devices and Simulators → select device → View Device Logs, and export available crash/watchdog reports. Check Organizer's Crashes for distributed builds. On iPhone, Settings → Privacy & Security → Analytics & Improvements → Analytics Data may contain crash and `JetsamEvent` reports. Preserve the original report privately, then extract the event date, process, app build, binary UUIDs, exception/termination fields and relevant frames into a sanitized investigation record. Device reports can contain paths and account or document details; they are not automatically copied into Flint's sanitized store.

For watchdog investigations, correlate the report's termination evidence with the last saved stages and a Time Profiler/Points of Interest recording. For jetsam, retain the process memory/limit evidence; a missing final journal entry is insufficient. Attach available symbolicated frames matched to UUIDs. Explicitly record absent reports, missing symbols and unavailable device fixtures. MetricKit is delayed/optional and does not guarantee every termination report. Apple documents [MetricKit delivery](https://developer.apple.com/documentation/metrickit/mxmetricmanager) and its [stack-frame schema](https://developer.apple.com/documentation/metrickit/mxcallstacktree/jsonrepresentation()).

### Simulated matching exercise (2026-10-06)

The final phase-2 simulator build (app version 1.0, build 1, based on `dc3da15` plus this working-tree change) `Flint.app/Flint.debug.dylib` reports arm64 UUID `9D2853AE-A8A1-3B80-BEB4-C0406939EAAA` using `xcrun dwarfdump --uuid`. A simulated crash frame with that UUID, architecture arm64, address 42 and offset 10 can be matched to this exact binary, while a frame with a different UUID must be rejected. These numeric frames are synthetic and do not establish a real crash or valid code address. Generated `/tmp/flint-phase2-final-symbols.dSYM` with `xcrun dsymutil`; `dwarfdump --uuid` confirmed the same UUID and arm64 architecture. This matches a synthetic frame to this simulator build; it does not replace a release archive or physical-device report. No physical-iPhone crash/watchdog/jetsam report, Dropbox fixture or Instruments trace has been collected for this phase.

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

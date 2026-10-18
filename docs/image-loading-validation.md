# Phase 5 image-loading validation

Users need to keep reading and editing while provider images load. This record separates automated checks from the real-source and Dropbox checks still needed before the original device failure can be considered resolved.

## Build and device

- Branch: `codex/lazy-image-loading`, based on `ecaa464`, with the phase 5 working-tree changes.
- App: version 1.0, build 1.
- Simulator: iPhone 17, iOS 26.5.
- Physical device: iPhone 17, iOS 27.0.1 (24A446).
- A signed build was installed and launched successfully on the physical device.

## Automated coverage

The new tests check downsampling limits, file-version changes, shared requests, independent cancellation, cache eviction, memory warnings, invalid images, paths outside the vault, attachment replacement, layout without rereading source files, photo staging lifetime, foreground deadlines, and cancellation of a blocked viewer read.

The full suite also checks Files, photo-library, and camera insertion through controlled source results. It verifies visible loaded-image bounds, captions, insertion position, surrounding text, managed assets, relative Markdown references, saved contents, source removal, relaunch, failed-save retry, and fullscreen dismissal.

Debug accessibility uses prepared-load state. Its saved-file snapshot runs separately in the background. The snapshot checks whether referenced files can be read; successful image decoding is verified by the visible prepared-image assertions.

## Failures investigated

The first build failed because three new assertions read actor-owned cache state synchronously. The assertions now await that state before checking it.

The first complete simulator run passed all 118 tests. Further cancellation and photo-deadline tests brought the suite to 122 tests, which also passed on the simulator.

The first complete phone run passed 116 tests and failed six. Device evidence showed equivalent app-container paths under `/private/var/` and `/var/`. Discovery used a character count from one form to remove the prefix from the other, corrupting note and folder paths. Image preparation also standardized paths on the UI thread, making missing-file handling depend on the path alias.

A focused regression test reproduced truncated paths twice before the fix. It expected `Projects/iOS/Seed.md` and `Daily.md`, but received `OS/Seed.md` and an empty path. Discovery now resolves both folder identities on a worker before deriving relative components. The path regression passed after that fix. A second check then reproduced the remaining creation-to-discovery identity mismatch. Both operations now return resolved note URLs, so opening a newly created note uses the same identity as the refreshed list. Image text preparation now builds an unverified address without filesystem standardization. The loader validates the resolved address before coordinating a read. Existing image-path assertions compare resolved file identities instead of requiring one spelling of an iOS path.

## Final automated results

- Full required simulator suite: **124 passed, 0 failed, 0 skipped**. Log: `/tmp/flint-phase5-final-simulator.log`. Result: `/tmp/flint-derived-data/Logs/Test/Test-Flint-2026.10.18_21-12-12-+1300.xcresult`.
- Full signed iPhone suite: **124 passed, 0 failed, 0 skipped**. Log: `/tmp/flint-phase5-final-phone.log`. Result: `/tmp/flint-phase5-device/Logs/Test/Test-Flint-2026.10.18_21-12-14-+1300.xcresult`.
- Both complete runs include the path and creation-identity fixes and their regression test. The intermediate phone run passed 121 tests and failed three before those fixes were complete. No unexplained passing retry was accepted.
- The normal app was relaunched on the iPhone after the test suite completed.
- Main specs and the change pass strict OpenSpec validation. Archive reconciliation advisories remain for the broader change; no archive was attempted.

## Real-source checks still required

The automated phone tests substitute source results. They do not exercise the system Files picker, a real Photos selection, camera capture, or permission denial.

For each real source, record selection or capture, cancellation, insertion, save, and reopening. Record permission denial where applicable. Use a disposable note and verify its Markdown and image remain intact. The real-source checks in task 5.6 remain pending until these outcomes are recorded.

The broader Dropbox matrix, Instruments main-thread trace, transient-memory measurements, and diagnostic-export acceptance remain pending under phase 7. A successful simulator or fixture-based phone run does not establish that the reported Dropbox hang or termination is fixed.

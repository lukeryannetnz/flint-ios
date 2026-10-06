# Tasks

## 1. Implement this behavior and test it

- [x] 1.1 Implement action IDs, step timings and final results; test that a timeout followed by late completion produces one final result plus one later observation.
- [x] 1.2 Implement the privacy rules; test errors containing paths, note text, account information and passwords and verify none appear in saved logs.
- [x] 1.3 Implement log size/age/waiting-entry limits and recovery from damaged entries; test full/slow storage and expiry without blocking note operations.
- [x] 1.4 Document log fields and how to read them using macOS Console and Instruments, Apple’s performance tools; provide a sample that clearly identifies a failed step.

## 2. Check the complete result

- [x] 2.1 After code or configuration changes, run the full Flint simulator suite from AGENTS.md and record the result; explain and resolve failures rather than relying on an unexplained passing retry.
- [x] 2.2 Check the implementation against the examples in this spec, update the main specs to match verified behavior, and leave required iPhone tests pending until evidence is recorded.

## Validation record

- Full AGENTS.md suite on iPhone 17 / iOS Simulator 26.5: **49 passed, 0 failed, 0 skipped**. Result: `/tmp/flint-derived-data/Logs/Test/Test-Flint-2026.10.04_16-39-01-+1300.xcresult`.
- Release simulator build: passed (`/tmp/flint-debug-log-release.txt`).
- Strict change/main-spec validation and `git diff --check`: passed.
- Earlier attempts: sandbox access to CoreSimulator was denied; an Xcode source-membership error was corrected. The first runnable suite failed one new timeout test because it compared action duration with time since logger startup; the assertion was corrected to check nonnegative duration and monotonic event ordering. The subsequent full run passed after that correction, not an unexplained retry.
- Real-iPhone Dropbox, Console and Instruments performance checks: **pending**. Simulator success does not establish that the reported physical-device hangs or crashes are fixed.

## PR #23 review fixes — 2026-10-06

- Accumulated drop counts stay pending until their counter entry is successfully written. A regression test covers a backlog, repeated storage failure and recovery, verifying all 2,002 missing entries are reported once.
- Error classification uses the failed step and explicit platform evidence to distinguish corrupt bookmarks, text corruption, coordination failures, unreadable images, unavailable providers and unavailable downloads. Unknown errors remain unknown, and private descriptions/domains are excluded.
- Full required iPhone 17 simulator suite: **51 passed, 0 failed, 0 skipped** (`/tmp/flint-debug-log-review-tests-final.txt`). Release simulator build and strict OpenSpec/whitespace checks passed.
- The first review run failed the old queue test because it counted 512 admitted entries plus the separate loss-counter record as 513 waiting entries. The test now checks admitted entries separately and verifies the loss count; the subsequent full run passed after this explained correction.
- Physical-iPhone validation remains pending.

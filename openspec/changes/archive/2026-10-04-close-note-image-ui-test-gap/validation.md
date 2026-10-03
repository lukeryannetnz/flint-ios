# Validation Evidence

## Diagnostic runs

- First inline-image UI test (`/tmp/flint-image-red.log`): expected failure before fixture launch and image observation existed.
- First harness run (`/tmp/flint-image-green.log`): image loaded and had nonzero bounds; caption assertion failed because the test queried a static-text element while UIKit exposed the content as the text view. Corrected the query to the actual text view.
- Initial multi-case run (`/tmp/flint-image-flow-red.log`): the same content-query error was reproduced; Files insertion reached the system picker before the deterministic substitute was wired and stalled. Cancelled the diagnostic run, implemented picker-result substitution, and added bounded diagnostic execution.
- Subsequent diagnostic run (`/tmp/flint-image-flow-green.log`): runner installation/launch failed with Mach IPC error -308 before test execution. Simulator test activity overlapped another workspace test run. This is recorded as an infrastructure failure, not a passing validation result.

## Release isolation

- Release simulator build (`/tmp/flint-image-release.log`): succeeded.
- Final Release simulator build (`/tmp/flint-image-release-final.log`): succeeded after the last harness-code changes. Symbol inspection of the release app found no `ImageWorkflowTestSupport` symbols.

- Final Release build including the failure-injection change (`/tmp/flint-image-release-complete.log`): succeeded. Symbol inspection found neither `ImageWorkflowTestSupport` nor `ImageWorkflowSaveFailure` in the Release app.

## Save failure and recovery

- `/tmp/flint-save-red.log`: the new save-recovery UI test failed at the expected missing error-alert assertion before failure injection was implemented.
- `/tmp/flint-save-green.log`: passed with a Debug-only filesystem write failure. The test verifies error reporting, unchanged saved markdown, retained unsaved text, a readable managed asset referenced by the draft, successful real save on retry, and image rendering after termination/relaunch.
- The agreed asset policy retains assets referenced by unsaved edits; orphan cleanup is outside this change.

## Full suite

The first full simulator suite passed (`/tmp/flint-image-full-tests.log`), including four UI cases and the real-file persistence integration tests. The content-query failures were fixed; runner infrastructure failures remain recorded above. The six-case UI suite and all unit/integration tests subsequently passed (`/tmp/flint-image-final-tests.log`). After correcting UI-target inheritance of local signing settings, the required full command passed again (`/tmp/flint-image-verified-tests.log`). All six UI cases passed: camera, existing image, Files, missing image, photo library, and viewer preservation.

Final required full simulator run (`/tmp/flint-image-complete-tests.log`): **TEST SUCCEEDED**. All unit/integration tests and all seven UI cases passed, including save-failure retention/retry and viewer preservation. All 18 implementation tasks are complete.

## Device validation

This change introduces Debug-only source substitutes and failure injection and extracts unchanged production picker callback bodies into shared helpers. It does not change production source-adapter behavior or permissions, so a physical-device smoke test is optional under the agreed rule. No physical-device smoke-test outcome is claimed.

For future changes that trigger the requirement, record the tested commit, device and iOS version, affected sources, selection/capture, insertion, save/reopen, cancellation, and applicable permission-denial outcomes. If no suitable device is available, completion remains pending.

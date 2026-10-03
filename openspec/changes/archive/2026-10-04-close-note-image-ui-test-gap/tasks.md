## 1. Test Harness

- [x] 1.1 Add FlintUITests to the shared Flint scheme alongside existing FlintTests integration coverage, following design.md.
- [x] 1.2 Add deterministic vault fixtures containing markdown notes and local image assets.
- [x] 1.3 Add a simulator-safe launch path that opens the fixture vault without requiring manual Files picker interaction.
- [x] 1.4 Add Debug-only source substitutes and read-only persistence observations; keep ordinary launches unchanged and test hooks absent from release builds.

## 2. Rendering and Viewer Coverage

- [x] 2.1 Verify successful inline-image loading, visible bounds, and caption content; an accessibility identifier alone is insufficient.
- [x] 2.2 Verify viewer presentation and dismissal preserve editor content and saved markdown with no pending unsaved changes.
- [x] 2.3 Add coverage for a missing or invalid image reference so the broken-image state remains non-crashing and the surrounding note remains readable.

## 3. Insertion Coverage

- [x] 3.1 Exercise Files, photo-library, and camera selections separately through deterministic substitutes and the real source callbacks and editor insertion flow.
- [x] 3.2 Verify the inserted image is copied into the note-adjacent managed asset folder.
- [x] 3.3 Verify saved relative references at the selected cursor position, surrounding text preservation, and resolution inside the managed folder within the vault.
- [x] 3.4 Remove the original import file where applicable, terminate and relaunch without reseeding, and verify the image renders from the saved vault asset.
- [x] 3.5 Test save-error reporting, retention of the unsaved edit and referenced asset, and successful persistence on retry.

## 4. Validation

- [x] 4.1 Confirm the new image workflow coverage runs in the required simulator test lane.
- [x] 4.2 Run the full Flint test suite with the required command.
- [x] 4.3 Update any stale documentation or archived checklist language discovered while implementing the coverage.
- [x] 4.4 Record any test failures and investigate them; do not count an unexplained failure as validated because a retry passes.
- [x] 4.5 Record device-evidence requirements and classify this change; when production source-adapter behavior or permissions change, record a physical-device smoke test before completion, or leave validation pending if no device is available.
- [x] 4.6 Verify a release build excludes the test setup, source substitutes, failure injection, and persistence snapshots.

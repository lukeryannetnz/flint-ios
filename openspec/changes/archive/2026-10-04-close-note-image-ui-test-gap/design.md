# Design

## Context

See `proposal.md` for motivation and `specs/testing-workflow/spec.md` for acceptance criteria. Flint currently has an application target and an app-hosted `FlintTests` unit-test target in the shared Flint scheme. Existing tests cover image imports, paths, markdown serialization, and attachment construction. They do not drive the note surface or viewer.

The editor and system source callbacks live in `VaultBrowserView.swift`. File and photo selections pass URLs into the import flow; camera selections pass a UIImage. The editor then inserts the resulting markdown image through its existing command path. Vault opening and note persistence are owned by `AppModel` and the real file service.

## Goals / Non-Goals

**Goals:**

- Exercise UI behavior through a separate `FlintUITests` target while retaining existing unit coverage and adding filesystem integration assertions in `FlintTests`.
- Keep test setup isolated, deterministic, and absent from release builds.
- Observe persisted output independently of editor state, so an in-memory attachment cannot stand in for a saved image reference.

**Non-Goals:**

- Automating Apple's picker UI, permission dialogs, or camera hardware.
- Adding external test frameworks, changing the vault format, or redesigning image presentation.

## Decisions

### Use UI tests for gestures and integration tests for persistence

Add `FlintUITests` to the shared Flint scheme's test action so the required simulator command runs both targets. Reuse the existing test Debug/Release xcconfig files so optional device signing reads the contributor's untracked Local.xcconfig and no team identifier is committed. UI tests launch the application, select fixture notes, inspect image/caption and broken-image presentation, open and dismiss the viewer, and insert images through the editor. Integration tests use the real file service and model for detailed managed-file and saved-markdown assertions.

Unit tests alone cannot establish that gesture routing or presentation works. UI tests alone make filesystem assertions unnecessarily difficult across the application-container boundary. Combining them covers these distinct responsibilities without replacing existing tests.

### Create isolated fixtures inside the application container

A Debug-only launch configuration enables a named image-workflow fixture and a unique run identifier. The application creates a fresh fixture vault inside its own test directory and opens it through the normal model flow, without persisting it as the contributor's normal vault selection. Fixtures include a valid image and caption, a missing image surrounded by readable text, and an editable note with identifiable text around a known insertion position.

Test teardown removes only its own fixture directory. A relaunch for persistence verification reuses the same run's vault without reseeding or overwriting it. Independent test cases receive separate directories. This avoids depending on simulator media, Files providers, or external paths supplied by the runner.

Alternatives are a shared fixture vault, which leaks state between tests, or manual Files selection, which adds platform interactions unrelated to the image behavior being checked.

### Substitute source results at the picker boundary

Under the explicit Debug test configuration, selecting Files, photo library, or camera provides a deterministic source result instead of presenting a system picker. Each substitute feeds the same application callback used by its production source. Files and photo cases supply local image URLs; the camera case supplies a generated UIImage and exercises the real JPEG import path.

All cases continue through the real import service, editor insertion command, text-change handling, save, and reload. The substitute must not write note markdown directly or manufacture a completed insertion. Camera availability in this explicit test configuration is deterministic even on a simulator without camera hardware; normal availability logic remains in use for ordinary launches.

Using system pickers would add permission and media-state variability. Calling import services directly would bypass the editor behavior this change is intended to test.

### Observe visible state and persisted output separately

Provide stable accessibility identifiers and meaningful accessibility content for the note surface, image/caption or broken-image state, source controls, and viewer dismissal. Image assertions must reflect an actual loaded attachment or image view; an identifier or test flag that is present regardless of loading is insufficient. Tests verify surrounding text remains readable for missing images and select a known editor insertion position between fixture text markers.

UI tests cannot assume direct filesystem access to the application container. A Debug-only, read-only test snapshot reports the actual note file contents and managed asset information after normal save completion. It reads from disk, exposes values for assertion through the test accessibility surface, and never mutates notes or supplies canned success values. Integration tests independently inspect files with the real service.

Viewer tests compare editor content and persisted markdown before presentation and after dismissal, confirm the same note is visible, and verify no pending unsaved changes remain. Rendering assertions combine successful image loading, visible image bounds, and captions when present; screenshot comparison is reserved for separate visual-layout tests.

Each insertion-source test verifies the saved reference occurs between the text markers, surrounding content remains intact, the reference is relative, and the referenced managed asset exists and is readable within the vault. Remove the original import file for URL-based sources before terminating and relaunching the application. Camera cases use generated capture results without an original import file. Relaunch with the same saved vault without reseeding, resolve the reference into its managed folder, and verify loaded-image state and visible bounds again. Camera integration assertions additionally verify JPEG output.

### Exercise save failure without replacing successful persistence

Use deterministic save-failure injection in the test configuration to make the real save flow report an error. Assert that the editor retains the image edit and unsaved state. Remove the injected failure and retry through the normal save flow, then inspect the actual saved reference and managed asset. Imported assets referenced by an unsaved edit are retained after save failure so retry can succeed; orphan cleanup is outside this change. The save-failure/retry case belongs in this change. The Debug harness injects a filesystem write error at the save boundary, leaving successful saves on the real file-service path.

### Preserve validation failures and require device evidence when applicable

Record failed runs even when diagnostic retries pass. An unexplained failure prevents a successful validation claim. For changes to production image source-adapter behavior or permissions, require a recorded physical-device smoke test of affected real source workflows before completion. Debug-only source-result substitutes and extraction of unchanged callback bodies do not independently trigger this requirement. Record the tested commit, device/iOS version, affected sources, and selection/capture, insertion, save/reopen, cancellation, and applicable permission-denial outcomes. If a suitable device is unavailable, report simulator results and keep device validation pending. Unrelated changes retain optional device validation.

Fixed delays and screenshot-only comparisons are weaker alternatives: delays race with saving, and screenshots cannot establish portable storage or unchanged markdown.

### Keep test control out of release builds

Compile fixture creation, source substitutes, cursor-position setup, and persistence snapshots only in Debug builds, and activate them only through explicit test launch configuration. Ordinary Debug launches retain production behavior. Accessibility improvements that accurately describe user-visible state can remain in production.

## Risks / Trade-offs

- UI timing and autosave races → Use bounded waits for visible states and completed persistence; do not rely on fixed sleeps.
- Source substitutes could skip production wiring → Share the actual source callbacks and import/editor path, and exercise each source independently.
- App-container boundaries could weaken persistence checks → Read saved files through the read-only snapshot and corroborate storage behavior in integration tests.
- Fixtures could mask reload failures → Preserve the run's saved vault on relaunch and never reseed during the reopen assertion.
- Test hooks could leak into normal behavior → Require both Debug compilation and explicit test activation; verify a release build excludes the hooks during implementation validation.
- Accessibility assertions could pass without rendering → Assert actual loaded or broken attachment state alongside visible caption and surrounding text.
- System-picker failures remain outside automated coverage → Document this boundary explicitly and correct the archived checklist's broader completion claim.

## Migration Plan

No vault or user-data migration is needed. Add the test target and Debug harness, implement the scenario coverage, and run the full required simulator suite. Update the archived image-work checklist with an explanatory correction that distinguishes source callback coverage from platform picker validation. Remove the new target and test hooks together if rollback is needed; existing tests and vault storage remain usable.

## Settled Review Decisions

The user accepted retaining referenced assets while edits remain unsaved, including save-error/retry coverage in this change, and applying device validation to production adapter or permission changes rather than Debug-only substitutes. The device evidence fields and outcomes are defined above. This change does not intentionally change production picker behavior or permissions.

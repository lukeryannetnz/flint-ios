## Why

The recently merged note image work added unit coverage for path resolution, image import storage, markdown round-tripping, and rich text attachment modeling. The archived implementation checklist also marked UI or integration coverage for inline rendering, fullscreen viewing, and insertion flows as complete, but the current repository does not include an automated UI/integration test target that exercises those user-facing paths end to end.

This leaves the most gesture-heavy and permission-adjacent parts of note images vulnerable to regressions even though the lower-level services are tested.

## What Changes

- Add a new `FlintUITests` target alongside the existing unit tests for the note image workflows introduced by the `note-images` capability.
- Cover at least one seeded vault note with an existing markdown image reference and verify the image appears in the note surface.
- Cover opening an inline image in the fullscreen viewer and dismissing it, verifying the underlying note markdown remains unchanged.
- Use deterministic picker substitutes for Files, photo-library, and camera selections, exercising each source callback through Flint's real editor insertion flow.
- Add integration assertions against saved markdown and managed asset files, verifying relative references, insertion at the cursor, preservation of surrounding text, and rendering after reopening the note.
- Use isolated fixture vaults and test-only setup to avoid manual vault selection and shared state between tests.
- Keep system permission dialogs, platform picker interaction, and camera hardware outside the default automated lane; substitutes replace source selection, while Flint's import, insertion, save, and reopen behavior remain real.
- Ensure the new coverage runs as part of the required simulator test command.
- Verify loaded-image state and visible bounds, preserve editor and saved content during viewing, and prove persistence after removing the import source and relaunching without reseeding.
- Cover deterministic save failure and successful retry without losing the unsaved image edit.
- Treat unexplained test failures as failures even if retries pass, and require recorded device smoke testing for production image source-adapter behavior or permission changes before completion.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `testing-workflow`: Adds required automated coverage expectations for note image UI and integration workflows.

## Impact

- Affected areas: the new UI test target, existing integration tests, UI test launch configuration, isolated test fixtures, and image insertion test seams.
- Likely code touch points: `Flint.xcodeproj`, `FlintUITests/`, `FlintTests/`, `Flint/Views/VaultBrowserView.swift`, and test-only launch/configuration helpers.
- Risk: UI tests that depend on system pickers can become flaky, so the default lane should prefer deterministic fixtures or test seams while still validating Flint's own workflow behavior.
- Device availability can delay completion when production source-adapter behavior or permission changes require physical-device validation.

## Why

Flint's note experience currently treats images as an edge case: markdown can contain image references, but the native note surface does not yet make local images a first-class part of reading or authoring. Adding polished image support now closes a clear usability gap for note-taking, research, and field capture workflows.

## What Changes

- Add first-class support for markdown images in Flint notes, including resolving image references across nested vault folders instead of only handling same-folder assets.
- Render note images as responsive visual cards with preserved aspect ratio, captions derived from alt text, and a tap-to-expand viewer for zooming and panning.
- Add a professional image insertion flow in the note editor with photo library, camera, and file picker entry points.
- Import inserted images into managed vault storage and write standard markdown image references back into the note using stable relative paths.
- Apply automatic display sizing heuristics so inserted images feel intentional without forcing users to manage widths manually.

## Capabilities

### New Capabilities
- `note-images`: Rendering, viewing, importing, storing, and inserting images within markdown notes.

### Modified Capabilities

None.

## Impact

- Affected areas: markdown parsing/rendering, note editor surface, fullscreen media presentation, file import/camera flows, vault file storage, and note-related tests.
- Likely code touch points: `Flint/Models.swift`, `Flint/Views/VaultBrowserView.swift`, `Flint/ViewModels/AppModel.swift`, `Flint/Services/VaultFileService.swift`, and related test coverage.
- Platform considerations: Photos, camera, and file importer permissions; image downsampling/performance; local file URL resolution for in-vault assets.

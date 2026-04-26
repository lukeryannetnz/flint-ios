## 1. Rendering Foundations

- [x] 1.1 Extend markdown image parsing and local path resolution so note-relative references can target assets anywhere within the active vault.
- [x] 1.2 Add native note-surface rendering for embedded images with responsive thumbnail card styling, caption support, and graceful broken-image fallback.
- [x] 1.3 Add a fullscreen image viewer with tap-to-open, zoom, pan, and dismiss behavior from the note surface.

## 2. Authoring Flows

- [x] 2.1 Add an image insertion control to the note editor with photo library, camera, and Files picker entry points.
- [x] 2.2 Copy inserted images into a managed note-adjacent asset folder and serialize standard relative markdown image references back into the note.
- [x] 2.3 Apply automatic display sizing heuristics for inserted images based on orientation and source dimensions.

## 3. Validation

- [x] 3.1 Add unit coverage for markdown image parsing, vault path normalization, and markdown round-tripping for inserted images.
- [x] 3.2 Add UI or integration coverage for inline rendering, fullscreen viewing, and insertion flows from each source type.
- [x] 3.3 Run the full Flint test suite and verify no regressions in existing note-management behavior.

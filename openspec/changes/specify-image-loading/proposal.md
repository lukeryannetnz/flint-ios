# Proposal: Load and import images without freezing the screen

## Why

Flint currently reads some image files while laying out notes and opening or updating the fullscreen viewer. Large images can also consume far more memory than their on-screen size needs. Reading and preparing them should happen in the background with clear limits.

## What Changes

- Show text and a temporary image placeholder while an image loads; let users close a viewer immediately.
- Prepare images at the size needed for display and limit how many images and saved display copies use memory.
- Import Files/photo/camera images in background work and insert a reference only into the note that requested it.

For example: A note contains a large photo that Dropbox has not downloaded yet. The text should appear immediately with an image placeholder. If the user opens then closes the viewer, a later download must not reopen it or change a different note.

## Capabilities

### New Capabilities

- `image-loading`: Describe how images load and import in background work, using smaller display images so large or partly downloaded files do not freeze the app or exhaust memory.

### Modified Capabilities

- `note-images`: Images in notes and the fullscreen viewer.
- `testing-workflow`: The iPhone tests required before calling the work complete.

## Impact

This follows PR #18, which supplies the preceding part of the plan. This PR contains proposed behavior and test requirements; it does not change the app yet. Implementation and real-iPhone testing remain separate tasks.

The [original combined plan](https://github.com/lukeryannetnz/flint-ios/pull/14) remains available for reference. The folder names are kept stable for OpenSpec; the document headings use plain English.

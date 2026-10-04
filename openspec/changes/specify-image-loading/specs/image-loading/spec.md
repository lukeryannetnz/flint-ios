# Load and import images without freezing the screen

## Purpose

Describe how images load and import in background work, using smaller display images so large or partly downloaded files do not freeze the app or exhaust memory.

Status: proposed behavior, not yet implemented. The task list records the work and testing still needed.

## ADDED Requirements

### Requirement: Show text while images load in the background
The system SHALL read images and prepare smaller display copies in background work, showing stable placeholders meanwhile. Building formatted text, laying out the note, and creating/updating viewer screens SHALL not read or decode image files. Completed results SHALL apply only if they still belong to the current note or viewer request.

#### Scenario: An image is waiting or the viewer has been closed
- WHEN an image is unavailable, delayed, invalid or still being prepared for display
- THEN text stays readable/scrollable, captions and markdown stay unchanged, and failed images can be retried
- AND the fullscreen viewer shows progress and can be closed immediately
- AND an old result cannot reopen a closed viewer or change another note
- AND supported formats, aspect ratio/sizing, zoom/pan, vault-contained paths and portable references remain supported without rewriting source assets

### Requirement: Limit image preparation and memory use
The system SHALL create a smaller image directly from the source instead of first decoding the entire full-resolution image. At most one image SHALL be decoded at a time. Cache keys SHALL include the vault and resource identity, observed file version and requested display size; matching versions/sizes from different files SHALL not share an entry. Images in notes SHALL be at most 2048 pixels on their longest side, viewer images at most 4096, and reusable display-image cache memory at most 32 MiB.

#### Scenario: Different images have the same version
- WHEN two files have the same observed version and requested size
- THEN each displays its own image, with no cache collision between files or vaults

#### Scenario: A large image loads or iOS reports low memory
- WHEN image requests need the same file/version/display size
- THEN they share work or reuse the saved display copy rather than repeatedly reading it during ordinary layout changes
- AND memory warnings remove reusable copies and cancel optional waiting work
- AND temporary memory and the currently displayed viewer image are measured separately from the reusable-cache limit on an iPhone
- AND accessibility/UI tests confirm the actual prepared image and visible bounds without rereading the source

### Requirement: Import images in the background without losing text or assets
The system SHALL copy/encode Files, photo-library and camera images into note-managed storage away from screen updates, keeping source/destination permission until work finishes. It SHALL insert a portable relative file reference only after successful import, and only into the note request that started it.

#### Scenario: Import fails, is cancelled or finishes after changing notes
- WHEN a source read, copy or encode cannot finish for the original note
- THEN editor text and intended insertion position remain intact and the failed step is logged
- AND a delayed import cannot insert into another note
- AND cleanup of an imported-but-unused asset does not delete anything referenced by saved or unsaved text
- AND if saving the note fails, the inserted reference and asset remain available for retry
- AND successfully saved images still load after the original import source is removed and Flint restarts

### Requirement: Bound temporary memory during imports
At most one image import SHALL prepare or encode pixels at a time. Photo/camera imports SHALL prepare an image no larger than 4096 pixels on its longest side before encoding, release the picker’s original full-resolution image as soon as preparation allows, and encode to a file rather than holding a second full encoded image buffer in memory. File imports SHALL stream the copy without fully decoding the original, preserving its bytes. Files that cannot be safely prepared SHALL fail recoverably without altering note text.

#### Scenario: Large photo or camera input is imported
- WHEN a large source image is selected or captured
- THEN only one import prepares or encodes pixels, the prepared image is at most 4096 pixels on its longest side, and optional display decoding waits while import preparation occupies the image-processing slot
- AND iPhone measurements record peak temporary memory, including the picker input, and verify that imports do not accumulate full-resolution inputs or full encoded buffers
- AND source picker memory is reported separately rather than claimed to fit within the display-cache limit

### Requirement: Test loading and imports on an iPhone
The implementation SHALL include repeatable tests for delayed, unreadable and large images, memory limits/warnings, closed viewers and failed imports. It SHALL record real-iPhone Files/photo/camera and Dropbox checks before being declared validated.

#### Scenario: Check the complete image workflow on a device
- WHEN insertion, scrolling, viewer opening/closing, cancellation, denied permission and save/reopen are exercised on an iPhone
- THEN image decoding and temporary-source copying are absent from the screen-update thread, memory use follows the limits and text/markdown/assets remain intact
- AND the tested code version, device/iOS/Dropbox/source details and evidence are recorded
- AND required device checks remain pending when that evidence is unavailable

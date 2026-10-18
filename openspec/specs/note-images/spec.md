# Note Images

## Purpose

Users need to view and insert images in their notes. Those images must remain usable when the vault moves to another device, and missing images must not prevent reading the note.

This spec defines image display, insertion, and storage inside the active vault. An image reference is a Markdown link to an image file. A relative path locates that file from the note's folder. A managed asset folder is the folder Flint creates beside a note to hold its imported images. Alt text is the description included in a Markdown image reference; Flint also displays it as a caption.

## Requirements

### Requirement: Resolve markdown image references across the active vault
The system SHALL resolve markdown image references for an open note using the note's folder as the base location while allowing referenced assets to live anywhere inside the active vault, including vault-rooted paths.

#### Scenario: Resolve a sibling image reference
- **WHEN** an open note contains a markdown image reference to `diagram.png`
- **THEN** Flint loads the image file from the same folder as the note
- **AND** Flint renders that image inline in the note surface

#### Scenario: Resolve a nested relative image reference
- **WHEN** an open note contains a markdown image reference to `../shared/images/diagram.png`
- **THEN** Flint normalizes the path relative to the note's folder
- **AND** Flint renders the image if the resolved file remains inside the active vault

#### Scenario: Resolve a vault-rooted image reference
- **WHEN** an open note contains a markdown image reference to `/Attachments/diagram.png`
- **THEN** Flint resolves that path from the active vault root rather than the device filesystem root
- **AND** Flint renders the image if the resolved file exists inside the active vault

#### Scenario: Reject a path outside the vault
- **WHEN** an open note contains a markdown image reference that resolves outside the active vault
- **THEN** Flint does not load the external file
- **AND** Flint shows a broken-image state instead of rendering the asset

### Requirement: Render note images as responsive media cards
The system SHALL render embedded note images as image cards rather than plain file links.

#### Scenario: Render a large image inline
- **WHEN** Flint displays an embedded image whose source dimensions exceed the note column width
- **THEN** Flint shows the image as a bounded thumbnail card within the note content width
- **AND** Flint preserves the source aspect ratio
- **AND** Flint avoids horizontal scrolling in the main note surface

#### Scenario: Render image caption from markdown alt text
- **WHEN** an embedded markdown image includes alt text
- **THEN** Flint shows that text as secondary caption content below the image

#### Scenario: Render a missing image gracefully
- **WHEN** the referenced image file cannot be loaded
- **THEN** Flint shows a non-crashing broken-image placeholder in the note surface
- **AND** Flint keeps the rest of the note readable and scrollable

### Requirement: Open embedded images in a fullscreen viewer
The system SHALL let users inspect embedded note images in a dedicated fullscreen viewer.

#### Scenario: Tap an inline image to inspect it
- **WHEN** the user taps an embedded image while not editing the note
- **THEN** Flint opens a fullscreen viewer for that image
- **AND** the original note remains unchanged beneath the viewer

#### Scenario: Zoom and pan a fullscreen image
- **WHEN** the fullscreen image viewer is open
- **THEN** the user can pinch to zoom the image larger than the fitted size
- **AND** the user can pan the zoomed image
- **AND** Flint provides a clear dismissal gesture or control

### Requirement: Insert images from common sources
The system SHALL let users insert images from common capture and selection sources.

#### Scenario: Choose an image source while editing
- **WHEN** the user chooses to insert an image into an open note
- **THEN** Flint presents image source options that include the photo library, camera, and Files picker when those sources are available

#### Scenario: Insert an image from the photo library
- **WHEN** the user selects an image from the photo library for an open note
- **THEN** Flint imports that image into vault-managed storage for the note
- **AND** Flint inserts a markdown image reference for the imported asset at the current insertion point

#### Scenario: Insert an image from the camera
- **WHEN** the user captures a new photo from the insert image flow
- **THEN** Flint saves the captured image as a JPEG into vault-managed storage for the note
- **AND** Flint inserts a markdown image reference for the saved asset into the note

### Requirement: Store inserted images with stable relative references
The system SHALL keep inserted note images portable with the vault by copying them into managed storage inside the vault and writing relative markdown references.

#### Scenario: Create a managed note asset folder on first insert
- **WHEN** the user inserts the first image into a note that does not yet have managed image storage
- **THEN** Flint creates a note-adjacent asset folder for that note
- **AND** Flint copies the imported image into that folder before updating the note markdown

#### Scenario: Avoid filename collisions while importing
- **WHEN** Flint imports an image whose filename already exists in the note's managed asset folder
- **THEN** Flint preserves the existing asset
- **AND** Flint writes the new image using a collision-resistant filename

#### Scenario: Persist a relative markdown path
- **WHEN** Flint finishes importing an image for a note
- **THEN** the note markdown contains a standard markdown image reference
- **AND** the referenced path is relative to the note location rather than an absolute device-specific file path

### Requirement: Render existing readable vault image formats without migration
The system SHALL render existing vault images in supported readable formats, including HEIC, without forcing them to be transcoded during note loading.

#### Scenario: Open an existing HEIC image reference
- **WHEN** an open note references a `.heic` image that exists inside the active vault
- **THEN** Flint renders that image inline and in the fullscreen viewer if opened
- **AND** Flint does not rewrite the note markdown or transcode the asset merely to display it

### Requirement: Size images automatically
The system SHALL choose sensible default display sizing for inserted note images without requiring manual width selection during insertion.

#### Scenario: Insert a landscape image
- **WHEN** the user inserts a landscape image into a note
- **THEN** Flint renders that image at the readable note content width by default unless doing so would upscale a small source excessively

#### Scenario: Insert a portrait image
- **WHEN** the user inserts a portrait image into a note
- **THEN** Flint renders that image narrower than the full note content width
- **AND** Flint keeps the image visually centered within the content column

#### Scenario: Insert a very small image
- **WHEN** the user inserts an image whose source dimensions are smaller than Flint's normal content width
- **THEN** Flint avoids scaling the image up so aggressively that it appears blurry

### Requirement: Prepare images before rendering

Slow image files must not prevent users from reading or editing note text. Flint SHALL show a loading placeholder while a visible image loads. Failed images SHALL offer retry without changing the note's Markdown or caption.

Image path validation, including checks for symbolic links that leave the vault, SHALL run on a file worker. Text construction, layout, viewer updates, and accessibility queries SHALL not read image files. The viewer SHALL receive prepared images and allow immediate dismissal during loading.

Image reads SHALL use the shared provider executor and retain vault access until the worker finishes. Decoding SHALL use one separate worker. Inline images SHALL have a longest edge of at most 2048 pixels; viewer images SHALL have a longest edge of at most 4096 pixels. The reusable decoded cache SHALL use at most 32 MiB and identify images by file version and requested size. Memory warnings SHALL clear it and cancel optional queued requests.

#### Scenario: Scroll or change notes while an image loads

- WHEN an image leaves the visible area or its document is replaced
- THEN its optional request is cancelled
- AND late completion cannot update the replacement document
- AND ordinary layout changes use prepared pixels without reading the source again

#### Scenario: Retry or reopen an image after its file changes

- WHEN the user retries loading or opens an image again
- THEN Flint checks the observed file version on a worker before reusing cached pixels
- AND it loads the changed image if the observed version differs

### Requirement: Import selected images without UI-thread file copies

Users must be able to keep using Flint while an image is imported. Files selections SHALL pass to the existing asynchronous importer without a synchronous staging copy. Photo-library temporary files SHALL be copied before their callback returns, on a background worker, and removed after import finishes. Camera encoding SHALL stay on the provider worker. Waiting for Photos, copying its callback file, and importing that file SHALL share one 30-second foreground deadline. Staging failures SHALL be shown to the user.

#### Scenario: Leave a note during import

- WHEN a selected image finishes importing after the user changes notes
- THEN its result stays associated with the original note
- AND it does not insert into the new note or delete an asset referenced by saved or unsaved text

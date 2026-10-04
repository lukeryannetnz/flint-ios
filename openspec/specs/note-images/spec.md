# note-images Specification

## Purpose

Define portable markdown image references, inline media cards, fullscreen viewing and managed image insertion within Flint vaults.

Status: proposed revisions in this specification are not yet implemented; the associated change tasks track implementation and validation.

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
The system SHALL show embedded images as cards in the note, loading and preparing smaller display images in background work while text and layout remain usable.

#### Scenario: Render a large image inline
- WHEN an image is wider than the note column
- THEN Flint shows a thumbnail card within that column, preserving the image’s aspect ratio
- AND the note does not scroll horizontally

#### Scenario: Render image caption from markdown alt text
- WHEN the image reference includes alt text
- THEN Flint shows it as a secondary caption below the image

#### Scenario: Render a missing image gracefully
- WHEN the referenced file cannot be loaded
- THEN Flint shows an image-unavailable placeholder without crashing
- AND the rest of the note stays readable and scrollable

#### Scenario: Provider image is pending
- WHEN an embedded image has not finished loading
- THEN Flint shows a stable placeholder and caption
- AND constructing formatted text and laying it out do not read or decode the source file
- AND failed loading can be retried without rewriting markdown

### Requirement: Open embedded images in a fullscreen viewer
The system SHALL let users open embedded images in a fullscreen viewer that loads and prepares its image in background work and can be closed while loading.

#### Scenario: Tap an inline image to inspect it
- WHEN the user taps an embedded image while not editing
- THEN Flint opens its fullscreen viewer and leaves the original note unchanged beneath it

#### Scenario: Zoom and pan a fullscreen image
- WHEN the fullscreen viewer is open
- THEN the user can pinch to zoom beyond the fitted size, move around the zoomed image, and clearly dismiss the viewer

#### Scenario: Dismiss viewer before loading completes
- WHEN the user closes a viewer with a pending image read
- THEN Flint cancels its request and returns immediately to the unchanged note
- AND later results cannot reopen that viewer or replace another note

### Requirement: Insert images from professional note authoring flows
The system SHALL provide first-class image insertion from common capture and selection sources.

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
The system SHALL keep inserted note images portable with the vault by copying them into managed local storage and writing relative markdown references.

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

### Requirement: Apply automatic image sizing heuristics
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

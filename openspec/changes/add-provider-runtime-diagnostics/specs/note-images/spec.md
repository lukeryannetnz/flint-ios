## MODIFIED Requirements

### Requirement: Render note images as responsive media cards
The system SHALL render embedded note images as responsive media cards, asynchronously loading and downsampling source files while text and layout remain usable.

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

#### Scenario: Provider image is pending

- WHEN an embedded image has not finished loading
- THEN Flint displays a stable loading placeholder and caption
- AND file reads and decoding do not run in text construction or layout callbacks
- AND failed loading exposes retry without rewriting markdown


### Requirement: Open embedded images in a fullscreen viewer
The system SHALL let users inspect embedded note images in a dedicated fullscreen viewer that loads and downscales source content asynchronously and can be dismissed while loading.

#### Scenario: Tap an inline image to inspect it
- **WHEN** the user taps an embedded image while not editing the note
- **THEN** Flint opens a fullscreen viewer for that image
- **AND** the original note remains unchanged beneath the viewer

#### Scenario: Zoom and pan a fullscreen image
- **WHEN** the fullscreen image viewer is open
- **THEN** the user can pinch to zoom the image larger than the fitted size
- **AND** the user can pan the zoomed image
- **AND** Flint provides a clear dismissal gesture or control

#### Scenario: Dismiss viewer before loading completes

- WHEN the user dismisses a viewer with a pending image read
- THEN Flint cancels its request and returns immediately to the unchanged note
- AND late image results cannot reopen the viewer or replace another note



## ADDED Requirements

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

#### Scenario: The provider moves the vault before an image read

- GIVEN a note's image reference belongs to the selected vault
- WHEN the provider supplies a different folder address for that vault
- THEN the image worker resolves the reference under that current folder
- AND it uses a separate read claim for the image itself
- AND the note and stored image reference keep their original logical addresses

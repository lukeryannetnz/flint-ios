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

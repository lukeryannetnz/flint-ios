## MODIFIED Requirements

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

# note-management Specification

## Purpose

Define how Flint exposes markdown notes within a selected vault, including note discovery, note creation, rich text editing, markdown persistence, and autosave behavior.

## Requirements

### Requirement: Discover markdown notes in the active vault

The system SHALL list markdown files found anywhere inside the active vault.

#### Scenario: Enumerate vault contents

- GIVEN a vault contains files and folders
- WHEN Flint reloads notes for that vault
- THEN Flint includes regular files with `.md` or `.markdown` extensions
- AND hidden files are skipped
- AND each note is shown with its title and vault-relative path
- AND folders are ordered alphabetically using localized case-insensitive ordering
- AND notes within each folder are ordered by file creation date with the newest note first
- AND ties fall back to localized case-insensitive relative-path ordering

### Requirement: Show styled note previews in note lists

The system SHALL present a compact markdown-aware preview for each listed note so the sidebar matches the rendered document style instead of showing a flattened raw text dump.

#### Scenario: Render a markdown-aware preview in the recent notes list

- GIVEN a note contains markdown headings, emphasis, or list items
- WHEN Flint shows that note in the recent notes list
- THEN Flint displays a short preview excerpt that preserves meaningful markdown structure where space allows
- AND Flint omits a duplicated title heading when the note starts with a heading that matches the note title
- AND Flint styles the preview as secondary supporting content within the same card language used elsewhere in the app

#### Scenario: Render a markdown-aware preview in the folder note list

- GIVEN a note contains markdown content
- WHEN Flint shows that note in the folder browser list
- THEN Flint displays the same formatted preview treatment used by the recent notes list
- AND Flint truncates the preview to fit the list row without spilling into a full document rendering

### Requirement: Auto-select an available note

The system SHALL select a note automatically when notes exist and no current selection can be preserved.

#### Scenario: First note after reload

- GIVEN Flint has reloaded notes for the active vault
- AND no existing selected note can be matched in the refreshed list
- WHEN at least one note exists
- THEN Flint opens the first note in the sorted note list

#### Scenario: No notes in vault

- GIVEN Flint has reloaded notes for the active vault
- WHEN no markdown notes exist
- THEN no note is selected
- AND editor text is cleared
- AND unsaved state is cleared

### Requirement: Create markdown notes

The system SHALL create new notes as markdown files inside the active vault, using the current folder context when the user is browsing folders.

#### Scenario: Create note in vault root

- GIVEN a vault is active
- AND the user is not currently drilled into a subfolder
- WHEN the user creates a note named `Daily Note`
- THEN Flint creates `Daily Note.md` in the vault root
- AND the initial file contents are empty
- AND Flint reloads notes
- AND Flint opens the created note

#### Scenario: Create note in the current folder

- GIVEN a vault is active
- AND the user is browsing `Projects/iOS` in the folder-based note browser
- WHEN the user creates a note named `Daily Note`
- THEN Flint creates `Projects/iOS/Daily Note.md`
- AND the initial file contents are empty
- AND Flint reloads notes
- AND Flint opens the created note

#### Scenario: Create note with markdown extension

- GIVEN a vault is active
- WHEN the user creates a note whose name already ends with `.md`
- THEN Flint preserves that filename instead of appending another extension

### Requirement: Validate note names

The system SHALL reject invalid note names before creating a new note file.

#### Scenario: Empty note name

- GIVEN the user attempts to create a note
- WHEN the provided name is empty or whitespace only
- THEN the operation fails with a "Please provide a name." error

#### Scenario: Unsupported characters in note name

- GIVEN the user attempts to create a note
- WHEN the provided name contains `/` or `:`
- THEN the operation fails with an unsupported characters error that includes the rejected name

#### Scenario: Duplicate note name

- GIVEN the vault already contains a file with the requested note filename
- WHEN Flint attempts to create the note
- THEN the operation fails with an already exists error for that filename

### Requirement: Read note content into a rich text document

The system SHALL load the selected note's UTF-8 markdown source and present it as a native rich text document.

#### Scenario: Select an existing note

- GIVEN the active vault contains a note
- WHEN the user selects that note
- THEN Flint reads the note contents as UTF-8 markdown text
- AND Flint maps the markdown into Flint's native rich text document model before display
- AND Flint makes that note the selected note
- AND unsaved state is cleared

#### Scenario: Selected note no longer exists

- GIVEN a note has been selected previously
- WHEN Flint attempts to read or save it after the file is gone
- THEN the operation fails with a note missing error

### Requirement: Autosave rich text edits

The system SHALL autosave rich text edits shortly after the user stops typing.

#### Scenario: Debounced autosave

- GIVEN a note is selected
- WHEN the user edits the rich text document
- THEN Flint marks the editor as having unsaved changes immediately
- AND Flint schedules a save after approximately 800 milliseconds of inactivity
- AND a later edit before that delay cancels the earlier pending autosave

#### Scenario: Manual save

- GIVEN a note has unsaved changes
- WHEN the user taps Save
- THEN Flint serializes the current rich text document back to markdown
- AND Flint writes the resulting markdown text to the selected note file
- AND unsaved state is cleared

### Requirement: Rich text only presentation and editing

The system SHALL present both reading and editing using the same rich text surface without exposing raw markdown in the main note experience.

#### Scenario: Read mode uses rich text presentation

- GIVEN a note is open
- WHEN Flint shows the note without the keyboard active
- THEN the note is displayed as rich text with Flint typography and spacing
- AND Flint presents the note title using the same visual scale as an H1 heading
- AND raw markdown syntax is not shown in the main note experience
- AND links remain tappable
- AND Flint does not show separate read mode or edit mode labels in the main note chrome

#### Scenario: Tap displayed content to edit in place

- GIVEN a note is open in rich text presentation mode
- WHEN the user taps within the content surface
- THEN Flint transitions that same content surface into editing mode
- AND Flint preserves the visible scroll position
- AND Flint places the insertion point at the tapped location or the nearest valid text position
- AND the note remains smoothly scrollable before and after entering edit mode
- AND the first vertical drag on an opened note scrolls the document immediately without getting stuck in text selection behavior
- AND read mode keeps scrolling constrained to the vertical axis for wrapped note content
- AND the keyboard is shown
- AND Flint does not navigate to a different screen or reveal raw markdown

#### Scenario: Initial rich text layout resolves to the visible note width

- GIVEN a note is opened in rich text presentation mode
- WHEN Flint finishes the initial note surface layout
- THEN Flint resolves line wrapping against the final visible text width for that viewport
- AND Flint does not leave the note horizontally scrollable because of stale initial layout metrics
- AND the note is vertically scrollable on the first drag without requiring a corrective pull to relayout

#### Scenario: Activate a link while not editing

- GIVEN a note is open in rich text presentation mode
- AND the note contains a link
- WHEN the user taps that link
- THEN Flint opens the link target
- AND Flint does not begin text editing for that tap

### Requirement: Rich text formatting controls

The system SHALL provide native-feeling controls for common note formatting.

#### Scenario: Show formatting controls for the current selection

- GIVEN the rich text editor is active
- WHEN the insertion point or selection changes
- THEN Flint updates formatting controls to reflect the current selection state
- AND Flint exposes controls for headings, lists, bold, italic, links, quotes, and code-style treatment
- AND Flint keeps those controls available through a refined toolbar, menu, or contextual control surface

#### Scenario: Apply inline formatting

- GIVEN the user selects text or has an insertion point in the rich text editor
- WHEN the user applies bold, italic, link, or code-style formatting
- THEN Flint updates the rich text document directly
- AND Flint preserves the user's active selection or insertion intent as closely as technically possible while the formatting UI is used
- AND Flint keeps the editor in editing mode while formatting controls are used
- AND the resulting formatting remains stable when the note is saved and reopened

#### Scenario: Bold and italic toggles apply semantic emphasis

- GIVEN the user selects text or places the insertion point in the rich text editor
- WHEN the user toggles bold or italic
- THEN Flint applies or removes semantic emphasis for that selection or typing state rather than relying on incidental font traits
- AND the updated emphasis is reflected immediately in the writing surface
- AND newly typed text follows the active bold or italic typing state until the user changes it

#### Scenario: Autosave status remains passive

- GIVEN the note has unsaved changes
- WHEN Flint shows autosave status in the note surface
- THEN Flint presents passive autosave feedback without a manual save button in that status chrome

#### Scenario: Production prototype hides debugging instrumentation

- GIVEN a note is open in the normal prototype build
- WHEN Flint renders the note surface
- THEN Flint does not show internal layout, scroll, or interaction diagnostics in the main note experience

#### Scenario: Apply block formatting

- GIVEN the user has an insertion point inside a paragraph
- WHEN the user applies a heading, list, or quote style
- THEN Flint converts the current paragraph or paragraphs into the selected block style
- AND Flint preserves surrounding content and selection as closely as technically possible

### Requirement: List and paragraph editing behavior

The system SHALL provide predictable list, paragraph splitting, and insertion behavior during rich text editing.

#### Scenario: Continue a non-empty list item

- GIVEN the insertion point is at the end of a non-empty list item
- WHEN the user presses return
- THEN Flint creates a new list item of the same list style on the next line

#### Scenario: Exit an empty list item

- GIVEN the insertion point is inside an empty list item
- WHEN the user presses return
- THEN Flint ends the list at that position
- AND the next paragraph becomes a normal body paragraph

#### Scenario: Split a paragraph

- GIVEN the insertion point is in a normal paragraph, quote, or heading
- WHEN the user presses return
- THEN Flint splits the block at the insertion point
- AND the new paragraph inherits the appropriate follow-on style for that block type

#### Scenario: Insert the first newline into an empty note

- GIVEN the selected note is empty
- WHEN the user presses return at the start of the rich text editor
- THEN Flint inserts a new empty body paragraph without crashing
- AND the editor remains responsive for continued typing

### Requirement: Empty state and placeholder behavior

The system SHALL provide a clear writing affordance when a note has no visible content.

#### Scenario: Empty note placeholder

- GIVEN the selected note has no visible rich text content
- WHEN the note is shown
- THEN Flint displays a refined placeholder inviting the user to start writing
- AND the first tap activates editing at the start of the document

### Requirement: Paste normalization

The system SHALL normalize pasted content into Flint's supported rich text model.

#### Scenario: Paste rich or plain text

- GIVEN the user pastes content into the rich text editor
- WHEN the pasted content contains unsupported fonts, colors, or excessive styling
- THEN Flint strips unsupported presentation attributes
- AND Flint preserves supported semantic formatting such as paragraphs, lists, links, bold, italic, quotes, and code-style treatment where possible
- AND Flint keeps the result visually consistent with Flint's writing surface

### Requirement: Markdown persistence remains internal

The system SHALL continue storing notes as markdown files while keeping that representation internal to the prototype UI.

#### Scenario: Save rich text to markdown files

- GIVEN the user edits a note through the rich text editor
- WHEN Flint saves the note
- THEN Flint serializes the rich text document into markdown compatible with the vault file
- AND Flint does not expose that markdown serialization in the main editing UI

#### Scenario: Preserve literal fenced code block text

- GIVEN a note contains a fenced code block
- WHEN Flint loads and later saves that note through the rich text editor
- THEN text inside the fenced code block remains literal code content
- AND Flint does not reinterpret inline markdown markers inside that code block as emphasis or links
- AND Flint does not introduce a phantom blank code line before the closing fence during round-trip serialization

#### Scenario: Preserve escaped markdown punctuation

- GIVEN a note contains literal markdown punctuation escaped for storage
- WHEN Flint loads and later saves that note through the rich text editor
- THEN the user sees the literal punctuation in the writing surface without added backslashes
- AND Flint preserves the stored escaped representation across save and reopen cycles

#### Scenario: Reformat multiple paragraphs without corrupting adjacent content

- GIVEN the user applies a block style across multiple paragraphs
- WHEN Flint rewrites those paragraphs into the selected block style
- THEN Flint reformats each targeted paragraph in sequence using the current document state
- AND Flint does not misalign or corrupt adjacent paragraphs because of stale source indices

### Requirement: Save status in the editor

The system SHALL communicate whether the current note still has pending edits.

#### Scenario: Unsaved edits are pending

- GIVEN the current note has unsaved changes
- WHEN the editor is shown
- THEN the status area displays `Autosaving…`
- AND Flint does not show a manual save button in that status area

#### Scenario: Note is fully saved

- GIVEN the current note has no unsaved changes
- WHEN the editor is shown
- THEN the status area displays `Saved`
- AND Flint does not show a manual save button in that status area

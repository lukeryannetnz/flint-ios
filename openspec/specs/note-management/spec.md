# note-management Specification

## Purpose

Define how Flint exposes markdown notes within a selected vault, including note discovery, note creation, editing, and autosave behavior.

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

The system SHALL create new notes as markdown files inside the active vault.

#### Scenario: Create note without extension

- GIVEN a vault is active
- WHEN the user creates a note named `Daily Note`
- THEN Flint creates `Daily Note.md` in the vault root
- AND the initial file contents are `# Daily Note` followed by a newline
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

### Requirement: Read note content

The system SHALL load the selected note's UTF-8 text into the editor.

#### Scenario: Select an existing note

- GIVEN the active vault contains a note
- WHEN the user selects that note
- THEN Flint reads the note contents as UTF-8 text
- AND Flint makes that note the selected note
- AND unsaved state is cleared

#### Scenario: Selected note no longer exists

- GIVEN a note has been selected previously
- WHEN Flint attempts to read or save it after the file is gone
- THEN the operation fails with a note missing error

### Requirement: Autosave note edits

The system SHALL autosave note edits shortly after the user stops typing.

#### Scenario: Debounced autosave

- GIVEN a note is selected
- WHEN the user edits the note text
- THEN Flint marks the editor as having unsaved changes immediately
- AND Flint schedules a save after approximately 800 milliseconds of inactivity
- AND a later edit before that delay cancels the earlier pending autosave

#### Scenario: Manual save

- GIVEN a note has unsaved changes
- WHEN the user taps Save
- THEN Flint writes the current editor text to the selected note file
- AND unsaved state is cleared

#### Scenario: Save when inline editing ends

- GIVEN a note is open in rendered document mode
- AND the user has entered inline editing from the rendered document
- WHEN the editor loses focus because the keyboard is dismissed
- THEN Flint writes the current editor text to the selected note file immediately
- AND unsaved state is cleared
- AND Flint returns to the rendered document view

### Requirement: Inline editing from the rendered document

The system SHALL let the user begin editing directly from the rendered markdown document without navigating to a separate editor screen.

#### Scenario: Tap rendered document to edit in place

- GIVEN a note is open in rendered document mode
- WHEN the user taps within the rendered document surface
- THEN Flint replaces the rendered document with an inline editor in the same document area
- AND the inline editor is focused so the keyboard is shown
- AND the inline editor preserves the rendered document width and visual frame within the viewport
- AND the current note text remains the editing source of truth

#### Scenario: Activate a link from the rendered document

- GIVEN a note is open in rendered document mode
- AND the rendered document contains a link
- WHEN the user taps that link
- THEN Flint opens the link target
- AND Flint does not enter inline editing for that tap

#### Scenario: Show formatting controls while inline editing

- GIVEN a note has entered inline editing from the rendered document
- WHEN the keyboard is shown
- THEN Flint shows markdown editing controls alongside the keyboard
- AND the document content area continues to match the rendered document frame

### Requirement: Save status in the editor

The system SHALL communicate whether the current note still has pending edits.

#### Scenario: Unsaved edits are pending

- GIVEN the current note has unsaved changes
- WHEN the editor is shown
- THEN the status area displays `Autosaving…`
- AND the Save button is enabled

#### Scenario: Note is fully saved

- GIVEN the current note has no unsaved changes
- WHEN the editor is shown
- THEN the status area displays `Saved`
- AND the Save button is disabled

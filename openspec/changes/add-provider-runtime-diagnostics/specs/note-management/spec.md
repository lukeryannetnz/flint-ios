## MODIFIED Requirements

### Requirement: Auto-select an available note

The system SHALL select a note automatically when notes exist and no current selection can be preserved.

Note-list refresh SHALL update metadata without launching background navigation tasks. Vault opening SHALL establish a selection or pending-content state before returning usable metadata; content loads SHALL be explicit, cancellable, and tied to the current selection generation. Note creation SHALL open only its created note, and metadata refresh after saving SHALL NOT launch fallback navigation.

#### Scenario: Open another vault

- GIVEN a note from a previous vault is selected
- WHEN Flint opens another vault
- THEN Flint resolves previous unsaved edits through persistence or an explicit retain/discard choice before replacing editor state
- AND the first available note has a selected or pending-content state when usable metadata is published
- AND unavailable content does not block the browser
- AND previous editor text is never saved into the new vault

#### Scenario: Create a note without delayed selection changes

- WHEN Flint creates a note in a vault with existing notes
- THEN the created note is selected before creation returns
- AND refreshing the list does not schedule another note to open later

#### Scenario: Refresh metadata after saving

- GIVEN the selected note remains in the vault
- WHEN Flint saves edits and refreshes the note list
- THEN Flint updates the selected note metadata without re-reading its content
- AND the editor retains the saved text

#### Scenario: First note after reload

- GIVEN Flint has reloaded notes for the active vault
- AND no existing selected note can be matched in the refreshed list
- WHEN at least one note exists
- THEN Flint explicitly begins loading the first note in the current sorted note list
- AND any later user selection invalidates that fallback load

#### Scenario: No notes in vault

- GIVEN Flint has reloaded notes for the active vault
- WHEN no markdown notes exist
- THEN no note is selected
- AND editor text is cleared
- AND unsaved state is cleared

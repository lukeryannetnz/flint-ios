## MODIFIED Requirements

### Requirement: Auto-select an available note
The system SHALL automatically choose a note when notes exist and the current selection cannot be kept. Refreshing file details SHALL not start unexpected note changes. Opening a vault SHALL establish a selected or loading-note state when it first shows file details; content reads SHALL be explicit, cancellable and tied to that selection. Creating a note SHALL open only the created note, and saving SHALL not trigger background fallback navigation.

#### Scenario: Open another vault
- GIVEN a note from the old vault is selected
- WHEN Flint opens another vault
- THEN it saves previous unsaved edits or obtains an explicit keep/discard choice before replacing editor state
- AND it selects the first available note or shows that its content is loading when file details appear
- AND unavailable content does not block the browser and old editor text is never saved into the new vault

#### Scenario: Create a note without delayed selection changes
- WHEN Flint creates a note in a vault containing other notes
- THEN the created note is selected before creation returns
- AND refreshing the list does not schedule another note to open afterward

#### Scenario: Refresh metadata after saving
- GIVEN the saved note still exists
- WHEN Flint saves edits and refreshes its file details
- THEN it updates those details without rereading editor content
- AND the editor retains the saved text

#### Scenario: First note after reload
- GIVEN Flint has refreshed the active vault’s note list and cannot keep the previous selection
- WHEN the list contains a note
- THEN Flint explicitly starts loading the first note in the current sorted list
- AND a later user selection makes that earlier loading request obsolete

#### Scenario: No notes in vault
- GIVEN Flint has reloaded the active vault’s note list
- WHEN no markdown notes exist
- THEN no note is selected, editor text is cleared and unsaved state is cleared

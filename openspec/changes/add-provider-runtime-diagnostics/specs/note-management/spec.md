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

### Requirement: Programmatic selection does not request navigation

When the browser synchronizes its selection with the model, it SHALL not issue another note read for that same selected URL. Only a different user-requested URL SHALL start navigation; synchronization SHALL not cancel a newer pending read or restore an older selection.

#### Scenario: Initial read overlaps browser appearance

- WHEN the model publishes an initial selection while another explicit note read is pending
- THEN browser appearance and selection synchronization do not reread the previous note
- AND the explicit read retains its generation unless the user changes selection

### Requirement: Reconcile pending browser selection

The model SHALL publish pending note selection separately from retained editor content. Failed or cancelled navigation SHALL reset that selection to the retained note, allowing the failed row to be selected again immediately. Late completion SHALL not reset a newer pending selection.

#### Scenario: Retry a failed or cancelled row

- WHEN a note load fails or the user cancels it
- THEN the browser returns selection to the retained note
- AND selecting the requested row again starts a fresh read without selecting another row first
- AND publishing pending selection does not dispatch a duplicate read

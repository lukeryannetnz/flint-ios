## MODIFIED Requirements

### Requirement: Auto-select an available note

The system SHALL select a note automatically when notes exist and no current selection can be preserved.

Automatic note-list continuation and save metadata refresh SHALL update metadata without launching background navigation tasks. Explicit user-requested discovery refresh SHALL reconcile a missing clean selection at completion, opening the first remaining note or clearing the editor for an empty vault, only if the selection generation is unchanged. Missing destinations with unsaved text SHALL retain that text and report the failure instead of discarding it or redirecting a write. Vault opening SHALL establish a selection or pending-content state before returning usable metadata; content loads SHALL be explicit, cancellable, and tied to the current selection generation. Note creation SHALL open only its created note, and metadata refresh after saving SHALL NOT launch fallback navigation.

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

### Requirement: Read note content into a rich text document

The system SHALL load the selected note's complete UTF-8 markdown source, bounded to 8 MiB, and present it as a native rich text document. Pending or failed loads SHALL expose progress or retry separately from editable content; the browser SHALL remain usable.

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

### Requirement: Distinguish discovery and preview states

The browser SHALL distinguish discovery in progress, incomplete discovery with retry, and a successfully empty vault. Visible rows SHALL request previews on demand and distinguish omitted, pending, unavailable, empty, and truncated excerpts. Refresh notes SHALL be available in the browser; invalidation after save or explicit refresh SHALL renew visible-row demand without requiring scrolling.

#### Scenario: Enumeration fails after usable metadata

- WHEN a later batch fails
- THEN previously discovered notes remain visible and selectable
- AND the browser offers discovery retry instead of showing an empty-vault success

#### Scenario: Selected file is removed outside Flint

- WHEN explicit discovery refresh establishes that the selected file is absent
- THEN an unchanged clean selection opens the first remaining note or clears the editor if none remain
- AND a later user selection takes precedence
- AND unsaved text for the missing destination is retained with a recoverable error

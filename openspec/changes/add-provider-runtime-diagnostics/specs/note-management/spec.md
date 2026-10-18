## MODIFIED Requirements

### Requirement: Auto-select an available note

When a vault contains notes and Flint cannot keep the current selection, Flint SHALL select a note from the current list.

Flint SHALL show notes as soon as it has usable file details. It SHALL load note text separately and allow that load to be cancelled. Each request SHALL belong to the current vault and selection, so an older result cannot replace a newer choice.

When discovery continues in the background, later batches SHALL add file details without changing the user's selection. Creating a note SHALL open that note only. Refreshing file details after saving SHALL update the selected note without reading its text again or opening another note.

#### Scenario: Open another vault

- GIVEN a note from one vault is selected
- WHEN the user opens another vault
- THEN Flint saves pending edits or asks the user to retain or discard them before replacing the editor
- AND Flint selects or begins loading the first available note when file details are ready
- AND a note that cannot be read does not block the browser
- AND text from the previous note is never saved into the new vault

#### Scenario: Create a note without a later selection change

- WHEN Flint creates a note in a vault that already has notes
- THEN Flint selects the created note before creation finishes
- AND a later file-list refresh does not open another note

#### Scenario: Refresh file details after saving

- GIVEN the selected note still exists
- WHEN Flint saves edits and refreshes its file details
- THEN Flint updates the selected note's details without reading its text again
- AND the editor keeps the saved text

#### Scenario: Load the first note after a refresh

- GIVEN Flint refreshed the active vault's note list
- AND Flint cannot keep the current selection
- WHEN the refreshed list contains at least one note
- THEN Flint starts loading the first note in the current order
- AND a later user selection cancels that fallback load

#### Scenario: The vault has no notes

- GIVEN Flint refreshed the active vault's note list
- WHEN the vault contains no Markdown notes
- THEN Flint selects no note
- AND clears the editor text and unsaved state

### Requirement: Model selection changes separately from note reads

The browser SHALL not request another read when it updates its selection to match the model. A different URL chosen by the user SHALL start a new read. Selection updates SHALL not cancel a newer read or restore an older selection.

#### Scenario: The browser appears while an initial read is pending

- WHEN the model publishes its initial selection while a note read is pending
- THEN showing the browser does not read the previously selected note again
- AND the pending read keeps its request identity unless the user chooses another note

### Requirement: Keep the requested note separate from the displayed note

The model SHALL publish which note is being requested separately from the note text still shown in the editor. If a read fails or is cancelled, the browser SHALL return to the displayed note so the user can try the failed row again. A late result SHALL not change a newer pending selection.

#### Scenario: Retry a failed or cancelled read

- WHEN a note read fails or the user cancels it
- THEN the browser selects the note whose text is still displayed
- AND choosing the failed row again starts a new read without first choosing a different row
- AND publishing the requested selection does not start a duplicate read


## ADDED Requirements

### Requirement: Preserve note paths across equivalent folder URLs

On a device, iOS may use different file addresses (URLs) for the same folder. For example, a symbolic link is another path to an existing folder. Flint SHALL resolve those addresses to the same actual folder before deriving note paths. It SHALL preserve each note's path relative to the vault and reject files outside that vault.

Creation and discovery SHALL return the same logical address for a note, using the selected vault address and the note's relative path. Workers SHALL resolve that address under the folder supplied by the provider for each operation. This allows Flint to select a newly created note even if the provider moves its folder.

#### Scenario: Discovery returns resolved file URLs

- GIVEN the selected vault URL and discovered file URLs use different paths for the same folder
- WHEN Flint discovers `Projects/iOS/Seed.md` and `Daily.md`
- THEN their vault-relative paths are `Projects/iOS/Seed.md` and `Daily.md`
- AND the browser shows `Projects` as the nested folder and `Daily.md` at the vault root

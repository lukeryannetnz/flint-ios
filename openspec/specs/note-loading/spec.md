# Load notes gradually and keep unsaved edits safe

## Purpose

Describe how Flint lists notes without reading every file first, loads previews only when needed, and saves the correct version without losing newer edits.

Status: proposed behavior, not yet implemented. The task list records the work and testing still needed.

## Requirements

### Requirement: List files before reading all their contents
The system SHALL show file details in limited batches without reading every preview or image first. It SHALL preserve supported file extensions, include regular files rather than folders, skip hidden files, preserve relative paths and keep existing sorting rules. Between batches it SHALL let requested reads/saves take priority; failed partial listing SHALL remain visible and clearly incomplete.

#### Scenario: Some file details or previews cannot be loaded
- WHEN these reads fail or stall
- THEN notes already found remain available, errors are logged and previews show waiting/unavailable states
- AND previews are read only for visible or recently requested notes, using at most 64 KiB of source and only complete UTF-8 text characters
- AND stored previews use at most 4 MiB of memory and are refreshed when a file version changes or the user explicitly refreshes
- AND a preview that was not requested, was shortened, was unavailable or was successfully read as empty has a distinguishable state

### Requirement: Keep the browser usable while a selected note loads
The system SHALL load selected-note contents separately, with a cancellable request ID. When needed it SHALL automatically select a note once from the current sorted list, without later results overriding user choice. Editable reads SHALL enforce an 8 MiB file-content limit as bytes arrive; failed or partial reads SHALL not become empty editable notes.

#### Scenario: The selected note is unavailable or too large
- WHEN its contents cannot be read or exceed the limit, including growth while loading
- THEN the browser remains usable and shows that the note is loading or could not be loaded
- AND the user can choose another note without an earlier request later replacing it
- AND partial text cannot be saved over the source and original markdown is unchanged
- AND preparing the note’s formatted text does not synchronously read its images

### Requirement: Save the right version to the right file
The system SHALL remember each save’s original destination, iOS file permission, text version and action ID, and save versions in order after the typing delay. Finishing an older save SHALL not mark newer text saved. Failed/timed-out saves SHALL retain editor text; navigation SHALL save it first or ask the user to keep a recovery copy or explicitly discard it.

#### Scenario: The user types or changes notes while a save is running
- WHEN new text is entered before an earlier save finishes
- THEN the earlier result cannot replace or mark the newer text saved
- AND a timed-out save remains an unknown result, keeps its original destination, and cannot overlap a retry
- AND leaving the note either saves it or keeps a protected local recovery copy separate from debug logs, unless the user explicitly discards it
- AND refreshing file details does not reload editor text or describe a successful write as failed because a later refresh failed
- AND switching vaults cannot save the previous note’s text into the new vault

#### Scenario: Recover retained edits after restarting
- WHEN Flint launches with a protected recovery copy
- THEN it discovers that copy without requiring the original provider file to be readable, and offers to restore or explicitly discard the edits
- AND the copy identifies its original vault/note and text version; recovered text is never silently written to a different note or over newer source content
- AND if the source differs or cannot be checked, the user can compare and choose a destination or keep the copy for later
- AND a copy is removed only after its contents are confirmed saved to the chosen destination or the user explicitly discards it
- AND cancelling recovery or a failed save retains the copy for the next attempt

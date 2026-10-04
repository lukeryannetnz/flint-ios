# Flint glossary

Shared language for Flint's notes, vaults, and file loading. See the [domain model](docs/domain-model.md) for relationships and examples.

## Vaults and files

**Vault**: A folder chosen by the user that contains their Markdown notes, images, and any subfolders.
_Avoid_: Workspace, database when referring to a vault.

**Active vault**: The vault the user is currently browsing or editing in Flint.

**Note**: A Markdown document stored as a file in a vault. Notes with the same filename in different folders are different notes.

**Note list**: The collection of notes Flint has discovered in a vault, with details used to browse them.

**File details**: Information about a file, such as its name, location, and modification date, separate from its contents.

**Preview**: A short excerpt of a note shown while browsing the note list.
_Avoid_: Summary when referring to an excerpt rather than a generated summary.

**File provider**: The service or app that makes a vault accessible through Files, such as Dropbox or local storage.

**Listed file**: A file whose entry is visible to Flint, even if its contents cannot yet be read.

**Downloaded file**: A file whose contents have been transferred to the device. Downloading alone does not establish that Flint has permission to read it.

**Available file**: A file whose contents Flint can read at that moment.
_Avoid_: Synced when the intended meaning is readable now.

## Editing and images

**Unsaved edits**: Changes in the editor that have not been confirmed as saved to the note file.

**Saved note**: The version of a note whose contents have been confirmed as written to its file.

**Image asset**: An image file in the vault that a note can display.

**Image reference**: A link in a note that identifies an image asset. The reference and the image file are separate things.

**Imported image**: A copy of an image placed in the vault for use in a note.

## Troubleshooting and recovery

**Debug log**: Flint's record of app actions, timings, and errors used to investigate problems.
_Avoid_: Diagnostic journal, diagnostic ledger.

**Crash report**: A report containing evidence about an unexpected termination of Flint.

**Recovery**: The process of returning to a usable app after opening a vault or note fails or is interrupted.

**Recovery copy**: A separate copy of unsaved note text kept so the user can recover their edits.
_Avoid_: Backup when referring specifically to unsaved edits.

# Proposal: Load notes gradually and keep unsaved edits safe

## Why

Building the note list currently reads every note for its preview, which can make Dropbox download far more than the user needs. Once reads and saves run in the background, Flint also needs to handle typing and switching notes while older work is still finishing.

## What Changes

- Show file names and dates as they are found; read preview text only for notes the user can see or recently requested.
- Keep the browser usable while a selected note loads, and reject incomplete or oversized editable files safely.
- Remember which text version and destination a save belongs to, and retain edits when saving or navigation fails.

For example: Flint starts saving version A of a note. The user types more, creating version B before the save finishes. Finishing A must not mark B as saved, replace B in the editor or save it into a different vault.

## Capabilities

### New Capabilities

- `note-loading`: Describe how Flint lists notes without reading every file first, loads previews only when needed, and saves the correct version without losing newer edits.

### Modified Capabilities

- `note-management`: Automatic note selection and refreshing file details.

## Impact

This follows PR #17, which supplies the preceding part of the plan. This PR contains proposed behavior and test requirements; it does not change the app yet. Implementation and real-iPhone testing remain separate tasks.

The [original combined plan](https://github.com/lukeryannetnz/flint-ios/pull/14) remains available for reference. The folder names are kept stable for OpenSpec; the document headings use plain English.

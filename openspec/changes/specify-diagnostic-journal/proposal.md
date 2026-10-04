# Proposal: Debug logs that help explain failures

## Why

Flint can freeze while opening a Dropbox folder, but its error alert does not tell us which step got stuck. A saved debug log will show the sequence of actions and how long each took, even after the app restarts.

## What Changes

- Record the steps involved in opening, reading and saving notes and images.
- Keep related log entries together using identifiers for the app launch and the action being performed.
- Save the log on the iPhone with strict size, age and privacy limits.

For example: A useful log should show that opening a folder reached “waiting for Dropbox to allow a read,” then stopped there. It should not contain the folder name, note text or account details.

## Capabilities

### New Capabilities

- `diagnostic-journal`: Describe the debug log Flint will save on the iPhone so developers can see what the app was doing before a file-loading failure.

### Modified Capabilities

None.

## Impact

This is the first review in the five-part plan. This PR contains proposed behavior and test requirements; it does not change the app yet. Implementation and real-iPhone testing remain separate tasks.

The [original combined plan](https://github.com/lukeryannetnz/flint-ios/pull/14) remains available for reference. The folder names are kept stable for OpenSpec; the document headings use plain English.

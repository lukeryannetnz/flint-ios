# Crash reports, restart recovery and sharing debug logs

## Purpose

Describe how Flint collects available crash and freeze information, avoids reopening the same failing vault automatically, and lets the user share debug logs.

Status: proposed behavior, not yet implemented. The task list records the work and testing still needed.

## ADDED Requirements

### Requirement: Collect crash reports and notice when the screen stops responding
The system SHALL collect available platform reports for crashes, freezes, excessive CPU use and excessive disk writes. It SHALL keep the original event time range and app/build identity separate from when a report arrives. Missing or delayed reports SHALL be expected. Release debugging symbols SHALL be retained so crash addresses can be translated into useful code locations.

#### Scenario: A report arrives after the app restarts
- WHEN Apple delivers a report during a later launch
- THEN private information is removed, duplicate reports are stored once, and the report is linked to a previous action only if its time and app build match
- AND missing reports or uncertain links are stated explicitly
- AND an unfinished launch record is not treated as proof of a crash or its cause
- AND Flint does not try to continue normal Swift execution after a fatal native crash
- AND the documentation explains how to collect device reports for crashes, iOS closing an unresponsive app, and iOS closing an app that uses too much memory

#### Scenario: The app stops responding while it is on screen
- WHEN a regular check of the screen-update thread is delayed by at least two seconds
- THEN a separate monitor records a suspected freeze, the actions in progress and how long the freeze lasted if the app recovers
- AND it ignores time when the app is suspended in the background and limits repeated log entries
- AND it can record slow file work even if the screen-update thread or file worker is stuck

### Requirement: Offer recovery before repeating an interrupted launch
The system SHALL save a record before automatically reopening a vault, then record completion or a handled cancellation/failure. If that record is unfinished, it SHALL show Retry, Choose another vault and Export diagnostics before accessing the folder again. Recovery SHALL preserve the saved folder reference and the user’s files.

#### Scenario: Reopening the vault was interrupted
- WHEN the previous attempt has no finish record
- THEN Flint shows recovery before automatically reopening the vault and describes the interrupted attempt without asserting a crash cause
- AND the user can choose another vault or export logs without reading the problem folder
- AND the user can explicitly retry, subject to the limits on background file work

#### Scenario: A new launch record cannot be saved
- WHEN Flint cannot safely save a start record before reopening the vault
- THEN it offers recovery without automatically accessing the folder
- AND it explains that it could not save the safety record, without claiming an earlier interruption or crash
- AND choosing another vault and exporting logs remain available
- AND explicit retry must save a safety record before provider access begins

### Requirement: Let the user choose whether to share debug information
The system SHALL offer a versioned debug-information export from setup, recovery and the normal app screen. The user SHALL preview the kinds of information and time range, share through the system share sheet, and be able to clear saved history. No telemetry SHALL be uploaded automatically.

#### Scenario: Share logs while Dropbox is stuck
- WHEN the user chooses to export debug information
- THEN the export uses only saved app-local logs, timing summaries, privacy-filtered platform reports, previous-launch status, app build, iOS version and device model
- AND it states what reports/entries are missing, what was skipped and what remains unknown
- AND raw platform reports or unrestricted error dictionaries are not shared
- AND export errors are recoverable; only one temporary export of at most 20 MiB exists, and it is removed after sharing/cancellation or on the next launch
- AND clearing history removes retained reports and resets identifiers while preserving vault references, recovered edits and the minimum record needed to avoid another failed automatic launch

# Design: Load notes gradually and keep unsaved edits safe

## Context

Building the note list currently reads every note for its preview, which can make Dropbox download far more than the user needs. Once reads and saves run in the background, Flint also needs to handle typing and switching notes while older work is still finishing.

## Goals / Non-Goals

The goal is to answer: **Can the user reach the notes they need sooner without a delayed read or save losing their work?** This part defines the proposed behavior and its tests. Other PRs cover the remaining parts of the plan; the app has not been changed by these specs.

## Decisions

1. Separate finding files, reading preview text and opening the chosen note. Reading every preview during listing can trigger unnecessary Dropbox downloads.
2. Let user-requested work run between listing batches. Give each request an ID so a delayed result can be ignored after the user chooses another note.
3. Save a snapshot containing text version and original destination, in order. Store recovery copies of edits separately from debug logs so log export can never expose them.

## Risks / Trade-offs

The limits are proposed acceptance criteria, not measurements of the current app. Some iOS or Dropbox information may be unavailable; logs and test records must state what is missing. Notes and images retain their current file formats.

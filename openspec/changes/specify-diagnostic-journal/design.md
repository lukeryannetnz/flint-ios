# Design: Debug logs that help explain failures

## Context

Flint can freeze while opening a Dropbox folder, but its error alert does not tell us which step got stuck. A saved debug log will show the sequence of actions and how long each took, even after the app restarts.

## Goals / Non-Goals

The goal is to answer: **Will these logs tell us what failed without collecting private note data or making the app slower?** This part defines the proposed behavior and its tests. Other PRs cover the remaining parts of the plan; the app has not been changed by these specs.

## Decisions

1. Use a fixed set of log fields so a reviewer can check exactly what is collected. Free-form error text can contain filenames or note contents.
2. Use Apple’s logging tools and performance timing markers, plus a background writer for the saved debug log. Saving logs inside Dropbox would make the logs depend on the same file access that may be stuck.
3. This PR defines the log itself. Collecting crash reports, detecting freezes and letting a user export logs are covered by PR #16.

## Risks / Trade-offs

The limits are proposed acceptance criteria, not measurements of the current app. Some iOS or Dropbox information may be unavailable; logs and test records must state what is missing. Notes and images retain their current file formats.

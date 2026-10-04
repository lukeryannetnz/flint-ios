# Design: Background file loading that keeps the app responsive

## Context

Flint currently performs some file work on the same thread that updates the screen. If Dropbox pauses while supplying a file, loading indicators and taps can stop working too. File loading needs its own limited background capacity and a clear way back to a usable screen.

## Goals / Non-Goals

The goal is to answer: **Does this keep the screen usable when Dropbox is slow, including when an already-started read cannot be stopped immediately?** This part defines the proposed behavior and its tests. Other PRs cover the remaining parts of the plan; the app has not been changed by these specs.

## Decisions

1. Use a limited pool of background file workers. An unlimited new task for each file can accumulate stuck reads and exhaust resources; merely putting blocking work inside a Swift actor does not move it off the shared execution pool.
2. Treat “stop waiting on screen” separately from “the file operation has stopped.” Apple’s NSFileCoordinator manages shared file access; cancelling it cannot interrupt a read/write block that is already running.
3. Keep the iOS permission with the actual background operation until it finishes. A second worker slot lets the user try another vault while one folder is stuck.

## Risks / Trade-offs

The limits are proposed acceptance criteria, not measurements of the current app. Some iOS or Dropbox information may be unavailable; logs and test records must state what is missing. Notes and images retain their current file formats.

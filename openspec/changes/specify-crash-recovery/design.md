# Design: Crash reports, restart recovery and sharing debug logs

## Context

An iPhone can close Flint before it writes a final error message. On the next launch, opening the same Dropbox folder immediately can repeat the failure. Flint needs a safe restart path and a way to collect the information Apple makes available.

## Goals / Non-Goals

The goal is to answer: **Can the user recover and give us useful crash information without repeating the failure or sharing private notes?** This part defines the proposed behavior and its tests. Other PRs cover the remaining parts of the plan; the app has not been changed by these specs.

## Decisions

1. Use MetricKit, Apple’s app-performance reporting framework, alongside reports collected through Xcode. Neither a saved log nor Apple’s report delivery guarantees an explanation for every unexpected exit.
2. Check screen responsiveness from separate background work. A check running on the frozen screen-update thread would freeze too; time spent suspended in the background does not count.
3. Save a small “started reopening this vault” record first, but do not wait indefinitely to save it. If it cannot be saved, offer recovery instead of automatically opening the folder and describe a safety-record failure rather than an interrupted attempt. An explicit retry must save the record first.

## Risks / Trade-offs

The limits are proposed acceptance criteria, not measurements of the current app. Some iOS or Dropbox information may be unavailable; logs and test records must state what is missing. Notes and images retain their current file formats.

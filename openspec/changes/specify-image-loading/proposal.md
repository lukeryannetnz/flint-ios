# Proposal

## Why

Attachment layout and viewer creation/update synchronously read full-resolution files. Specify lazy loading and bounded decoding while preserving captions, portable markdown and imported assets.

## What Changes

- Define the behavior in `image-loading` and its acceptance scenarios.
- Preserve this part of the original proposal while making it reviewable independently.

## Capabilities

### New Capabilities

- `image-loading`: Define asynchronous bounded image rendering, viewer loading and source import for partially downloaded provider-backed assets.

### Modified Capabilities

- `note-images`: Render note images as responsive media cards, Open embedded images in a fullscreen viewer.
- `testing-workflow`: Provider diagnostics and asynchronous access require physical-device validation.

## Impact

Planning only; no app code or runtime configuration changes. Depends on the preceding spec PR; review this branch against its immediate predecessor.
Original reference: https://github.com/lukeryannetnz/flint-ios/pull/14 (preserved, superseded).
Review question: **How do large or pending images render and import without freezing or exhausting memory?**

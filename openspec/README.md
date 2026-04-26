# OpenSpec

This repository uses OpenSpec as a lightweight, checked-in source of truth for Flint's current behavior.

## Layout

- `openspec/specs/`: current functional specifications organized by capability
- `openspec/changes/`: proposed future changes and their spec deltas

## Current Specs

- `app-bootstrap`: launch and vault restoration behavior
- `vault-management`: creating and opening vault folders
- `note-management`: listing, creating, reading, editing, and autosaving markdown notes
- `testing-workflow`: default simulator testing and optional device validation

## Usage

Install OpenSpec with the official CLI when you want slash-command workflow support:

```bash
npm install -g @fission-ai/openspec@latest
```

Then use the specs in this directory as the repository's source of truth for current behavior and add future proposals under `openspec/changes/`.

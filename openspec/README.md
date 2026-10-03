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
- `development-workflow`: official repository-local OpenSpec skills for Codex

## Usage

The official Fission-AI/OpenSpec skills are installed under `.agents/skills/`.
Codex discovers them for this repository; invoke `$openspec-propose`,
`$openspec-explore`, `$openspec-apply-change`, or `$openspec-verify-change` to
start a workflow. All twelve published workflow skills are included.

These skills require the current official OpenSpec CLI:

```bash
npm install -g @fission-ai/openspec@latest
```

Then use the specs in this directory as the repository's source of truth for current behavior and add future proposals under `openspec/changes/`.

To refresh only the repository skills from the official source, run:

```bash
npx skills add Fission-AI/OpenSpec --agent codex --yes
```

Upstream source: https://github.com/Fission-AI/OpenSpec/tree/main/skills

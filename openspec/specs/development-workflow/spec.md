# Development Workflow

## Purpose

Define repository-local OpenSpec workflow support for Codex contributors.

## Requirements

### Requirement: Official repository-local skills

The repository SHALL provide the official Fission-AI/OpenSpec workflow skills under `.agents/skills/`, allowing Codex to discover them for this project.

#### Scenario: Contributor invokes an OpenSpec workflow

- WHEN a contributor opens this repository in Codex
- THEN the installed `openspec-*` skills are available by their declared names
- AND current behavior remains documented under `openspec/specs/`
- AND proposed changes remain under `openspec/changes/`

### Requirement: Preserve existing contributor setup

Installing repository-local skills SHALL preserve existing specifications, changes, root AGENTS.md instructions, and home-directory prompts.

#### Scenario: Skills are installed in an existing repository

- GIVEN Flint already contains specifications and an in-progress change
- WHEN official skills are installed
- THEN those documents and the contributor's global tooling remain intact

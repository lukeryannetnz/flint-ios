# Development Workflow

## Purpose

Contributors need to find the current requirements, propose changes, and describe Flint using consistent language. Clear documentation helps them understand the app before changing it.

This spec defines the repository's OpenSpec support, README overview, and shared vocabulary. OpenSpec keeps current requirements in `openspec/specs/` and proposed changes in `openspec/changes/`.

## Requirements

### Requirement: README overview

The root README SHALL explain Flint's scope. It SHALL link to `openspec/specs/` for current behavior and `openspec/changes/` for proposed changes. It SHALL not duplicate feature or specification lists.

The architecture overview SHALL use a simplified Mermaid diagram and plain-language descriptions of the main responsibilities. It SHALL describe how the parts fit together rather than list individual files.

#### Scenario: Reader explores the project

- WHEN a reader opens the root README
- THEN they can understand Flint's purpose and the relationship between the interface, app state, document conversion, and vault storage
- AND they can follow links to current specifications and proposed changes for details

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

### Requirement: Shared domain language

The repository SHALL define common Flint terms in root `GLOSSARY.md`. It SHALL explain the relationships between those terms in `docs/domain-model.md`. Specifications and review descriptions SHALL use these terms consistently and explain unfamiliar technical terms where needed. Existing machine identifiers MAY remain unchanged.

The glossary SHALL define vocabulary. It SHALL not define implementation contracts. The domain model SHALL describe concepts and relationships without listing implementation status or work in progress. Plans and status SHALL stay in the relevant change documents.

#### Scenario: Contributor describes logging and file availability

- WHEN a contributor writes a specification or review description
- THEN they use “debug log” for Flint's record of actions and errors
- AND they distinguish a listed file from a file whose contents can be read
- AND they use recovery for interrupted editing as well as failures while opening a vault or note
- AND they can refer to the glossary and domain model for the shared meaning

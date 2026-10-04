# Design

## Context

This is spec PR 4/5 replacing the preserved PR #14. Discovery currently reads every note to build previews, and introducing asynchronous saves creates revision/navigation races. Define incremental loading and data integrity as one document contract.

## Goals / Non-Goals

Goal: resolve **How do notes stay usable without reading the entire vault or losing edits?**. This PR defines behavior; implementation and device validation remain tracked work. Other layers have their own PRs.

## Decisions

1. Separate metadata enumeration, preview demand and selected content; whole-vault preview reads are the current download amplifier.
2. Use controlled batch scheduling and generation IDs to prevent later discovery/results from replacing a user choice.
3. Save immutable revision/destination snapshots and serialize writes; keep document-recovery storage separate from diagnostics.

## Risks / Trade-offs

Numeric budgets are initial acceptance limits, not measured performance. Platform/provider observations may be absent; tests and physical-device evidence must state uncertainty. The existing vault/markdown format is preserved.

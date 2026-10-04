# Design

## Context

This is spec PR 3/5 replacing the preserved PR #14. Main-actor synchronous coordination and enumeration can freeze the loading screen. Define background work, logical cancellation and resource lifetimes before migrating note and image callers.

## Goals / Non-Goals

Goal: resolve **How do we keep the UI responsive when file coordination cannot be stopped?**. This PR defines behavior; implementation and device validation remain tracked work. Other layers have their own PRs.

## Decisions

1. Use a dedicated bounded blocking executor, not unlimited detached tasks or blocking calls inside a cooperative actor.
2. Logical cancellation invalidates UI publication separately from worker completion; NSFileCoordinator.cancel cannot interrupt an already-running accessor.
3. Workers own security-scope leases until actual completion. A second global slot supports switching away from one blocked vault.

## Risks / Trade-offs

Numeric budgets are initial acceptance limits, not measured performance. Platform/provider observations may be absent; tests and physical-device evidence must state uncertainty. The existing vault/markdown format is preserved.

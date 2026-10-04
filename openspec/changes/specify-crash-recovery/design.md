# Design

## Context

This is spec PR 2/5 replacing the preserved PR #14. Hard terminations may leave no final log, while reopening the same stalled vault can repeat the failure. Define independent evidence collection and recovery without claiming that an interrupted launch proves a crash.

## Goals / Non-Goals

Goal: resolve **What can we know after a crash or freeze, and how does the user recover?**. This PR defines behavior; implementation and device validation remain tracked work. Other layers have their own PRs.

## Decisions

1. Use MetricKit and device/Organizer reports together; neither journal markers nor platform delivery guarantee the cause of every termination.
2. Monitor from an independent executor, excluding background suspension; logging on the stalled main actor cannot establish responsiveness.
3. Persist safety markers before restoration, but bound marker persistence; user recovery must not depend on a provider.

## Risks / Trade-offs

Numeric budgets are initial acceptance limits, not measured performance. Platform/provider observations may be absent; tests and physical-device evidence must state uncertainty. The existing vault/markdown format is preserved.

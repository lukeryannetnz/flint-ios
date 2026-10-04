# Design

## Context

This is spec PR 1/5 replacing the preserved PR #14. Alerts do not show which Dropbox operation stalled, and evidence disappears after termination. Define content-free correlated events and bounded local storage before adding collection or recovery behavior.

## Goals / Non-Goals

Goal: resolve **What evidence is useful, safe to retain, and cheap enough to collect?**. This PR defines behavior; implementation and device validation remain tracked work. Other layers have their own PRs.

## Decisions

1. Use typed events and allowlisted fields; arbitrary dictionaries make redaction difficult to audit.
2. Use unified logging/signposts plus a separate bounded app-local writer; provider-backed logging would share the failure being diagnosed.
3. This owns event/storage contracts. Hang monitors, platform payloads, export UI and recovery are reviewed in PR 2.

## Risks / Trade-offs

Numeric budgets are initial acceptance limits, not measured performance. Platform/provider observations may be absent; tests and physical-device evidence must state uncertainty. The existing vault/markdown format is preserved.

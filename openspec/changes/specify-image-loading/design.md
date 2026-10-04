# Design

## Context

This is spec PR 5/5 replacing the preserved PR #14. Attachment layout and viewer creation/update synchronously read full-resolution files. Specify lazy loading and bounded decoding while preserving captions, portable markdown and imported assets.

## Goals / Non-Goals

Goal: resolve **How do large or pending images render and import without freezing or exhausting memory?**. This PR defines behavior; implementation and device validation remain tracked work. Other layers have their own PRs.

## Decisions

1. Use Image I/O downsampling and a shared bounded image module; views receive prepared images instead of opening sources.
2. Cache by resource version and target size, and apply generation checking to attachments, viewers and imports.
3. Background picker staging/encoding retains access leases and managed-asset-before-reference ordering.

## Risks / Trade-offs

Numeric budgets are initial acceptance limits, not measured performance. Platform/provider observations may be absent; tests and physical-device evidence must state uncertainty. The existing vault/markdown format is preserved.

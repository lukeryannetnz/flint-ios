# Tasks

## 1. Implement and verify this contract

- [ ] 1.1 Verify delayed/duplicate platform reports retain original timestamps and build identity; test sanitization.
- [ ] 1.2 Verify interrupted and failed-marker launches enter recovery before provider access and preserve bookmarks.
- [ ] 1.3 Verify heartbeat thresholds, recovery duration and background suspension with a controlled clock.
- [ ] 1.4 Verify stalled-provider export, redaction, cleanup, clear history and export failure; document symbol collection and a sample report.

## 2. Integration acceptance

- [ ] 2.1 Run the full AGENTS.md Flint simulator suite after code/configuration changes, record results, and explain/resolve failures rather than accepting an unexplained passing retry.
- [ ] 2.2 Verify this change against its acceptance scenarios, reconcile main specs after implementation, and leave required physical-device validation explicitly pending until evidenced.

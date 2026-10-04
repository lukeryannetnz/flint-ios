# Tasks

## 1. Implement and verify this contract

- [ ] 1.1 Verify thread isolation, capacity, queue saturation and cancellation using controllable jobs.
- [ ] 1.2 Verify timeouts return without waiting for blocked accessors and late results cannot publish.
- [ ] 1.3 Verify access leases outlive UI cancellation and release after actual completion.
- [ ] 1.4 Record loading/cancel/retry UI checks and an iPhone Dropbox trace; retain uncertain outcomes and pending device status.

## 2. Integration acceptance

- [ ] 2.1 Run the full AGENTS.md Flint simulator suite after code/configuration changes, record results, and explain/resolve failures rather than accepting an unexplained passing retry.
- [ ] 2.2 Verify this change against its acceptance scenarios, reconcile main specs after implementation, and leave required physical-device validation explicitly pending until evidenced.

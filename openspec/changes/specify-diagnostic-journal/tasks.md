# Tasks

## 1. Implement this behavior and test it

- [ ] 1.1 Implement action IDs, step timings and final results; test that a timeout followed by late completion produces one final result plus one later observation.
- [ ] 1.2 Implement the privacy rules; test errors containing paths, note text, account information and passwords and verify none appear in saved logs.
- [ ] 1.3 Implement log size/age/waiting-entry limits and recovery from damaged entries; test full/slow storage and expiry without blocking note operations.
- [ ] 1.4 Document log fields and how to read them using macOS Console and Instruments, Apple’s performance tools; provide a sample that clearly identifies a failed step.

## 2. Check the complete result

- [ ] 2.1 After code or configuration changes, run the full Flint simulator suite from AGENTS.md and record the result; explain and resolve failures rather than relying on an unexplained passing retry.
- [ ] 2.2 Check the implementation against the examples in this spec, update the main specs to match verified behavior, and leave required iPhone tests pending until evidence is recorded.

# Tasks

## 1. Implement this behavior and test it

- [ ] 1.1 Implement gradual file listing; test sorting/filtering, partially completed listing and priority for requested reads/saves without eagerly reading note contents.
- [ ] 1.2 Implement preview reads and caching; test the 64 KiB/4 MiB limits, text cut in the middle of a UTF-8 character, refresh and waiting/unavailable/empty states.
- [ ] 1.3 Implement separate selected-note loading; test the 8 MiB limit, files growing while read, choosing another note and ignoring old results without making partial text editable.
- [ ] 1.4 Implement ordered saves and safe navigation; test typing during save, unknown write outcomes, keep/discard decisions, recovered edits after restart and original markdown integrity.

## 2. Check the complete result

- [ ] 2.1 After code or configuration changes, run the full Flint simulator suite from AGENTS.md and record the result; explain and resolve failures rather than relying on an unexplained passing retry.
- [ ] 2.2 Check the implementation against the examples in this spec, update the main specs to match verified behavior, and leave required iPhone tests pending until evidence is recorded.

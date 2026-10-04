# Tasks

## 1. Implement this behavior and test it

- [ ] 1.1 Implement collection of Apple reports and removal of private information; test late/duplicate reports and keep their original event dates and app builds.
- [ ] 1.2 Implement launch-start/finish records and the recovery screen; test interrupted launches and failed record writes before any folder access, preserving saved vault references.
- [ ] 1.3 Implement the two-second responsiveness check and freeze-duration logging; test with a controlled clock and exclude background suspension.
- [ ] 1.4 Implement preview/share/clear-history and export cleanup; test export during blocked file access, privacy filtering and export failure, and document how to read a matching crash report.

## 2. Check the complete result

- [ ] 2.1 After code or configuration changes, run the full Flint simulator suite from AGENTS.md and record the result; explain and resolve failures rather than relying on an unexplained passing retry.
- [ ] 2.2 Check the implementation against the examples in this spec, update the main specs to match verified behavior, and leave required iPhone tests pending until evidence is recorded.

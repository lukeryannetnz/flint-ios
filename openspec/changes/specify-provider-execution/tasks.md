# Tasks

## 1. Implement this behavior and test it

- [ ] 1.1 Implement limited background file workers; test screen-thread separation, two active jobs, one per vault, 32 waiting jobs and removal of cancelled jobs.
- [ ] 1.2 Implement five-second slow state and 30-active-second recovery; test a blocked read/write returns control to the screen and ignore results from obsolete attempts.
- [ ] 1.3 Keep iOS file permission until actual completion; test cancellation, switching vaults and balanced permission release.
- [ ] 1.4 Test loading, cancel/retry and unknown write outcomes; record an iPhone Dropbox performance trace and leave missing device checks pending.

## 2. Check the complete result

- [ ] 2.1 After code or configuration changes, run the full Flint simulator suite from AGENTS.md and record the result; explain and resolve failures rather than relying on an unexplained passing retry.
- [ ] 2.2 Check the implementation against the examples in this spec, update the main specs to match verified behavior, and leave required iPhone tests pending until evidence is recorded.

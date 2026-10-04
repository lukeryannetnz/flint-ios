# Tasks

## 1. Implement this behavior and test it

- [ ] 1.1 Implement smaller display images and their cache; test 2048/4096-pixel limits, one decoder, the 32 MiB cache, refresh/shared requests, distinct files with matching versions/sizes, and memory warnings.
- [ ] 1.2 Implement waiting placeholders and viewer cancellation; test readable text, unchanged captions/markdown, immediate close and ignored old results.
- [ ] 1.3 Implement background Files/photo/camera source handling; test single-import preparation, 4096-pixel photo/camera limits, streamed Files copies, file encoding, picker release and peak temporary memory, delayed/failed imports, insertion position, preserving referenced assets and save/reopen after source removal.
- [ ] 1.4 Record iPhone Dropbox and Files/photo/camera permission/cancel/retry checks and performance traces; keep missing device evidence explicit and run the full simulator integration suite.

## 2. Check the complete result

- [ ] 2.1 After code or configuration changes, run the full Flint simulator suite from AGENTS.md and record the result; explain and resolve failures rather than relying on an unexplained passing retry.
- [ ] 2.2 Check the implementation against the examples in this spec, confirm the already-updated main specs match the implementation and revise them before any further implementation changes, and leave required iPhone tests pending until evidence is recorded.

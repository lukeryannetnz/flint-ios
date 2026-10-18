# AGENTS.md

## Writing Requirement

Write specs and PR descriptions in plain English. Start by explaining the problem, who it affects, and why the change matters. Then describe the intended behavior.

Use short sentences and familiar words. Explain technical terms before using them. Keep one main idea per paragraph, and use concrete examples where they make the behavior easier to understand. Preserve precise requirements when simplifying the wording.

## OpenSpec Requirement

Before building any feature or making any code, spec, or configuration change in this repository, update the relevant OpenSpec documentation first.

Use the specs under `openspec/specs/` to define or revise the intended behavior before implementation work begins.

## Testing Requirement

After any code or configuration change in this repository, run the full Flint test suite before handing work back.

Use this command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project Flint.xcodeproj \
  -scheme Flint \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/flint-derived-data \
  test
```

Use a currently available iOS Simulator destination if `iPhone 17` is unavailable and still run the full suite.

For optional device validation, contributors may also run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project Flint.xcodeproj \
  -scheme Flint \
  -destination 'id=00008120-0008388A3C61A01E' \
  -derivedDataPath /tmp/flint-derived-data-device \
  -allowProvisioningUpdates \
  test
```

Device validation requires local signing configuration and a connected device destination.

# AGENTS.md

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
  -destination 'id=00008120-0008388A3C61A01E' \
  -derivedDataPath /tmp/flint-derived-data \
  -allowProvisioningUpdates \
  test
```

If the connected device destination changes, update the destination id accordingly and still run the full suite.

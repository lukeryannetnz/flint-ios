# Flint

Flint is a native SwiftUI markdown note-taking app built around user-selected vault folders in Files providers such as local storage and Dropbox.

## Current scope

- Create a vault by choosing a parent folder and supplying a custom vault name.
- Open an existing vault by selecting a folder from Files.
- Persist vault access with security-scoped bookmarks.
- List markdown notes stored directly in the vault.
- Create new markdown notes.
- Edit notes with autosave.

## Architecture

- `Flint/ViewModels/AppModel.swift`: app state and vault lifecycle orchestration.
- `Flint/Services/VaultBookmarkStore.swift`: bookmark persistence for reopening external folders.
- `Flint/Services/VaultFileService.swift`: coordinated file-system access for vault and note operations.
- `Flint/Views/`: onboarding, folder picker bridging, and the editor shell.
- `FlintTests/`: unit tests for the app model and file service.

## Signing

The committed project intentionally omits a fixed `DEVELOPMENT_TEAM` so contributors can select their own Apple development team in Xcode before running on a device.

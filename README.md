# Flint

Flint is a native SwiftUI markdown note-taking app built around user-selected vault folders in Files providers such as local storage and Dropbox.

![Flint launch artwork](/Users/lukeryan/src/flint-ios/Flint/Resources/Assets.xcassets/FlintBrandBoard.imageset/flint-brand-board.png)

Strike a spark. Keep every note in a markdown vault you own.

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

The repo uses `Configs/Local.xcconfig` for local-only signing overrides. The example file in `Configs/Local.xcconfig.example` shows the expected key. Contributors can create their own local override without committing team-specific settings.

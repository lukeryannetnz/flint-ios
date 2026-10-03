## Context

Flint already has partial markdown image awareness in its HTML renderer, but the primary native note experience is still text-centric. The current rich text codec maps headings, lists, quotes, links, and inline emphasis into a native attributed text surface, while embedded images are not modeled as first-class document elements. The requested change spans rendering, navigation, media import, and vault storage behavior, so it benefits from an explicit design before implementation.

## Goals / Non-Goals

**Goals:**

- Render markdown images from anywhere in the active vault, including nested relative paths such as `../images/photo.jpg` and deeper descendant paths.
- Present images attractively in the note surface with responsive thumbnails, preserved aspect ratio, and a fullscreen viewer that supports zooming and panning.
- Let users add images professionally from the photo library, camera, or Files picker without leaving the note workflow.
- Store imported assets in a predictable vault-managed location and insert stable relative markdown references back into the note.
- Choose sensible default display sizing automatically so common note-taking cases feel polished without immediate manual resizing controls.

**Non-Goals:**

- Advanced image editing such as crop, annotate, rotate, filters, or markup.
- Arbitrary drag-handle resizing in the first release.
- OCR, alt-text generation, or image search.
- Remote image downloading, syncing, or upload services beyond reading a markdown image URL if already present.

## Decisions

### 1. Introduce image support as a new `note-images` capability

The behavior is broad enough to deserve its own spec instead of scattering image rules across the existing note-management document. This keeps rendering, viewing, import, and storage expectations together while still allowing implementation to reuse the existing note pipeline.

Alternatives considered:
- Modify only `note-management`: rejected because image behavior would be hard to find and review as the spec grows.
- Split into multiple new capabilities: rejected for now because rendering and insertion are tightly coupled in the first release.

### 2. Resolve local image paths relative to the note first, with vault-aware traversal and vault-root support

Markdown image references will resolve from the note's containing folder so paths like `diagram.png`, `images/diagram.png`, and `../shared/diagram.png` work naturally. Flint should also support vault-rooted paths because many existing vaults keep attachments at the root, so a reference such as `/Attachments/photo.jpg` must resolve from the active vault root rather than the device filesystem. The core contract is that references may point anywhere inside the vault as long as they normalize to an in-vault file.

Alternatives considered:
- Limit support to same-folder assets: rejected because it does not satisfy the requested nested-folder behavior.
- Resolve every path from the vault root: rejected because it breaks standard markdown expectations for note-relative references.

### 3. Keep persisted markdown portable by writing standard image syntax

Inserted images should serialize back to plain markdown image syntax such as `![Sketch](../Note Assets/sketch.jpg)`. Flint's initial sizing behavior will be derived from image metadata and layout heuristics at render time rather than encoding proprietary width metadata into the note.

Alternatives considered:
- Store HTML `<img>` with custom width attributes: rejected because it reduces markdown readability and portability.
- Add Flint-specific sidecar metadata for widths: deferred until manual resizing exists and the extra complexity is justified.

### 4. Use a managed sibling asset folder for inserted images

When a user inserts an image, Flint should copy it into a folder adjacent to the note, such as `<Note Name> Assets/`, and generate collision-resistant filenames when needed. This mirrors common note-taking tools by keeping attachments close to the owning note without forcing a single global media bucket.

Alternatives considered:
- Store attachments in a vault-wide global folder: rejected because it becomes noisy and harder to reason about in large vaults.
- Reference external photo library or temp file URLs directly: rejected because the links are brittle and not portable with the vault.

### 5. Use automatic sizing heuristics for the first release

Flint should size embedded images based on orientation and pixel dimensions:
- landscape and square images expand to the readable content width,
- portrait images render slightly narrower and centered,
- very large assets appear as bounded cards with tap-to-expand,
- small images avoid aggressive upscaling beyond a quality threshold.

This approach gives a professional default similar to modern note apps without requiring manual resize controls in the first pass.

Alternatives considered:
- Always render every image full width: rejected because portraits and small images look clumsy.
- Require users to pick a size preset on every insert: rejected because it adds friction to a basic capture workflow.

### 6. Normalize camera captures to JPEG while preserving existing readable formats

Flint should save newly captured camera images as JPEG for broad portability, predictable previews, and simpler testing. Existing vault images in readable formats, including HEIC, should continue to render without forced migration so Flint can open current note libraries without rewriting assets.

Alternatives considered:
- Preserve HEIC for camera captures when available: rejected for v1 because it increases compatibility risk for exported or externally viewed vaults.
- Transcode every imported image to JPEG: rejected because it would unnecessarily rewrite existing assets from the photo library or Files picker.

### 7. Present images in a dedicated fullscreen viewer instead of inline zooming

Tapping an image in read mode should open an immersive viewer that supports pinch-to-zoom, panning, and simple dismissal. This keeps the editor surface stable and avoids mixing document scrolling with image manipulation gestures.

Alternatives considered:
- Inline pinch-to-zoom inside the note surface: rejected because gesture conflicts with note scrolling and editing are likely.
- Open images in a separate system app: rejected because it feels disconnected and unpolished.

## Risks / Trade-offs

- [Large vault assets can hurt performance] → Downsample for on-screen rendering, cache decoded previews, and load fullscreen assets lazily.
- [Camera and picker permissions can create flow friction] → Use clear source selection UI and fail gracefully back to the remaining import options.
- [Managed sibling asset folders may create many folders] → Keep naming predictable and create folders only when the first attachment is inserted.
- [Render-time auto-sizing may not satisfy every layout preference] → Start with good defaults and leave room for a later manual sizing extension if users need more control.
- [Path normalization must not escape the vault root] → Validate resolved URLs before rendering or importing and show a broken-image state for invalid paths.

## Migration Plan

1. Add the new `note-images` spec and implementation tasks without changing existing note files.
2. Implement read-only rendering and fullscreen viewing for existing markdown image syntax first.
3. Add image insertion flows and vault asset copying using standard markdown references, saving camera captures as JPEG.
4. Validate round-tripping by reopening edited notes and verifying the inserted images still resolve correctly.
5. If any issue is found, rollback is low risk because notes remain plain markdown and imported assets are additive.

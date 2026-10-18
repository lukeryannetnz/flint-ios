# Image loading and import

A slow image must not stop a user reading or editing a note. Visible images show a loading card while Flint prepares their pixels. Missing or unreadable images show a placeholder; tap it to retry. Captions and saved Markdown stay unchanged.

The fullscreen viewer loads its own larger image. It shows progress and a Retry action on failure. Close remains available during loading. Closing cancels that viewer's request; a late result cannot reopen it.

## Work and memory limits

`PreparedImageLoader` shares requests for the same vault, image path, and display size. Each caller can cancel independently. When the last caller leaves, the shared attempt is cancelled. Attachments request images only while visible and cancel pending requests when they leave the screen or their document is replaced.

File reads use the existing provider executor: two workers globally, one per vault, and at most 32 queued jobs. Each worker keeps its iOS access lease until it actually finishes. A 30-second foreground deadline limits the user-facing wait. Cancellation or timeout does not prove a blocked provider has stopped.

The file worker first resolves the logical image address under the vault folder supplied by the current coordinated root. It then makes a separate read claim for that image. It validates the image path, including symbolic links, under coordinated access. Images must stay inside the vault. It observes modification date, creation date, and file size before looking in the decoded cache. A cache miss is copied to an app-local temporary file. A separate worker downsamples that copy with Image I/O, without first decoding the full-resolution image.

Only one decode runs at a time. Inline images have a longest edge of at most 2048 pixels; viewer images have a longest edge of at most 4096 pixels. The reusable decoded cache holds at most 32 MiB, evicting the least recently used entries first. Images larger than that budget may be displayed but are not cached. Active views and temporary decoding memory are outside the reusable cache budget; a 4096-square RGBA viewer image alone can use about 64 MiB.

Memory warnings clear the cache and cancel optional pending image loads. Work already decoding keeps its temporary copy until actual return. It cannot refill a cache cleared by a warning. Visible cards may retain their prepared pixels. Cards release those pixels when they leave the screen, while keeping their measured bounds to avoid moving the text. Repeated loading placeholders share rendered cards. Layout changes redraw those pixels without filesystem access. Reopening or retrying an image checks the observed file version again.

## Image sources

Files selections pass directly to the asynchronous importer. The UI no longer makes a staging copy or starts security-scoped access itself. The import worker retains source and destination access, coordinates the copy, and creates the managed asset before inserting its relative Markdown reference.

Photo-library callback URLs exist only during the callback. Apple documents the [temporary file lifetime](https://developer.apple.com/documentation/foundation/nsitemprovider/loadfilerepresentation(fortypeidentifier:completionhandler:)) and the [internal callback queue](https://developer.apple.com/documentation/foundation/nsitemprovider). Flint copies the selected file on that background callback before returning. At most two callback copies run at once. The staged copy stays alive through actual import-worker completion, including after a timeout, and is removed afterward. Staging failures are shown instead of silently treating them as cancellation. Waiting for Photos, staging, and the vault import share one 30-second foreground deadline. Late Photos callbacks cannot publish a second result or import into another note. Camera JPEG encoding remains on the provider worker. These changes add no new permission requests.

Late import results stay associated with the original note. They cannot issue an insert command in another note. Existing explicit image recovery handles successful imports whose original caller timed out or became stale. No cleanup path deletes vault assets referenced by saved or unsaved text.

## Validation

Deterministic tests cover large-image downsampling, version changes, duplicate requests, independent cancellation, cache eviction, memory warnings, invalid images, vault escapes, attachment replacement, layout without source reads, and photo staging lifetime. Existing simulator UI tests cover Files/photo/camera insertion, cursor placement, captions, visible loaded-image bounds, fullscreen dismissal, save/reopen, and failed-save retry. Debug accessibility reads the attachment's prepared-load state; it does not reopen the file.

Physical-device validation remains required. Record the tested commit, device and iOS version, affected sources, selection or capture, cancellation, permission denial where applicable, insertion, and save/reopen. The Dropbox performance matrix and Instruments trace also remain required before claiming that the original device failure is resolved.

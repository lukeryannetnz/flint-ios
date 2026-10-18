# Note loading and edit recovery

Vault discovery reads metadata only. Each worker batch inspects at most 64 entries, then releases provider capacity so explicit reads and saves can proceed. Hidden items, non-regular files and symbolic links are excluded. Recent notes retain modification-date/path ordering; folders retain creation-date/path ordering. The first usable sorted batch supplies one initial selection. Later batches never replace a user selection.

The browser displays discovered notes immediately. Discovery progress reports an observed count, not a total or download percentage. Cancel stops discovery, marks the list incomplete, and leaves existing notes usable. Retry merges observed results and replaces the list only after complete enumeration. A failed or cancelled scan never claims an empty vault.

Visible rows request previews independently. Each reads at most 64 KiB, omits incomplete trailing UTF-8 sequences, and distinguishes pending, unavailable, empty, and truncated content. Preview entries share a 4 MiB budget and use observed modification dates and byte sizes; save and explicit discovery refresh invalidate the cache. Offscreen row tasks cancel their optional provider requests.

Selected notes have independent 30-second foreground deadlines. Reads enforce an 8 MiB source limit even if size metadata is missing or the file grows. Invalid UTF-8, missing files and oversized files never produce editable partial text. The browser remains available during pending reads; cancellation and selecting another note invalidate late results.

Saves capture the original destination and revision. An older save cannot mark newer edits clean; a metadata-refresh failure cannot turn a successful write into a failed save. Timed-out writes retain their actual outcome and prevent overlapping writes to that destination, including after switching notes or vaults.

When a save prevents navigation, Flint offers Stay, Retain edits and continue, or Discard edits and continue. Retain atomically stores the exact text, original vault and original note in protected local Application Support, excluded from backup and separate from diagnostic evidence. Failed retention keeps the unsaved editor in place. Discard clears editor edits, but cannot stop a write already executing inside a provider.

Use **Retained edits** in the browser toolbar to inspect saved destinations, restore into the original note in the matching open vault, or delete a copy. Restore loads the original note first and then applies the retained text as unsaved edits. Copies remain until explicit deletion, including after a later provider save fails. Nothing is automatically written back on relaunch. Recovery storage failure is shown and never clears unsaved text.

Simulator fault coverage does not establish physical-device Dropbox responsiveness. The overall change remains awaiting the iPhone/Dropbox matrix and Instruments validation, including accepted large-note formatting costs.

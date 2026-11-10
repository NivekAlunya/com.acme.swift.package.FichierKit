# FichierKit New Review Resolution Plan

## Objective

Resolve the latest FichierKit review findings while preserving iOS and tvOS compatibility, strict Swift 6 concurrency, atomic download semantics, deterministic pagination, and the no-commit review workflow.

## Review Assessment

### 1. Destructive download cleanup — confirmed bug

`AMSMB2Client.performDownloadFile` removes `localURL` before each network attempt and again on failure. If `localURL` already contains a valid file, a failed or cancelled transfer permanently deletes it.

This violates the package's atomic replacement guarantee and is inconsistent with the safer default `SMBClientProtocol.downloadFile` implementation.

### 2. Global cursor purge — confirmed bug

`SharesCursorStore.resetScope` clears every tracked scope when more than eight scopes exist. Resetting one directory can therefore invalidate cursors for unrelated active directories and cause unnecessary re-fetches.

Scope invalidation must be isolated to the requested key. Any global bound should use targeted eviction rather than clearing all active scopes.

### 3. Cursor-store growth — valid scalability concern

Cursor mappings can remain in the actor for the lifetime of a `SharesMediaSource` if scopes are created without corresponding resets. The current threshold only triggers while resetting a scope and does not provide a predictable least-recently-used policy.

Add bounded, targeted eviction with access tracking. Do not sacrifice unrelated active pagination contexts.

### 4. Missing direct unit coverage — partially confirmed

Existing tests already cover:

- Default range-based SMB downloads.
- Cancellation and `.part` cleanup.
- Existing-destination preservation for the protocol default implementation.
- Folder-first pagination behavior through `SharesMediaSource`.
- Several `SupportedMediaTypes` paths.

Missing or insufficiently isolated coverage remains for:

- `MediaSourceItemSortComparator` across every sort key and direction.
- `SharesCursorStore` hit, miss, reset, exhaustion, and eviction behavior.
- `AMSMB2Client.performDownloadFile` preserving an existing destination across retry failure and cancellation.

## Resolution Plan

### Phase 1 — Make AMSMB2 downloads atomic

File:

- `Sources/FichierKit/Sources/AMSMB2Client.swift`

Refactor `performDownloadFile` as follows:

1. Do not remove or modify `localURL` before a transfer succeeds.
2. For each retry attempt, create a unique sibling temporary URL:

   ```swift
   let tempURL = localURL
       .deletingLastPathComponent()
       .appendingPathComponent("\(localURL.lastPathComponent).\(UUID().uuidString).part")
   ```

3. Download with `SMB2Manager.downloadItem` into the temporary URL.
4. Forward cancellation and progress through the existing callback.
5. On cancellation or failure, remove only the temporary URL.
6. Before installation, check cancellation again.
7. If the destination exists, replace it with the completed temporary file.
8. Otherwise move the temporary file into place.
9. Ensure cleanup is idempotent when `replaceItemAt` or `moveItem` succeeds.
10. Keep retry behavior intact, but give each attempt a fresh temporary URL.
11. Preserve the existing destination if every attempt fails.
12. Leave the public `downloadFile` signature and `AMSMB2Client` actor isolation unchanged.

Review the behavior when `downloadItem` creates or partially writes a destination file. The only path supplied to `downloadItem` must be the unique temporary URL.

### Phase 2 — Fix cursor scope isolation

File:

- `Sources/FichierKit/Sources/SharesCursorStore.swift`

Change `resetScope` so it removes only:

- `cursorsByScope[scopeKey]`
- `exhaustedScopes` entry for `scopeKey`
- `maxTrackedPageByScope` entry for `scopeKey`

Do not clear all scopes as a side effect of resetting one scope.

Ensure all cursor reads and writes update access metadata for the relevant scope.

### Phase 3 — Add bounded LRU eviction

Keep the cursor store actor-isolated and introduce a bounded scope policy:

1. Define a documented maximum number of tracked scopes.
2. Track last access order per scope.
3. Refresh access order on cursor lookup, reset, and record operations.
4. When inserting a new scope beyond the limit, evict only the least-recently-used scope.
5. Never evict the scope currently being updated.
6. Remove all metadata for an evicted scope consistently.
7. Keep cursor behavior deterministic after eviction: a later request must safely restart from the appropriate initial cursor or page offset.
8. Avoid timers, detached tasks, or global mutable state.

If the store is only intended to live for one `SharesMediaSource`, document that lifecycle as well; the bound remains useful as protection against many folders or sort combinations within that lifetime.

### Phase 4 — Preserve cancellation and retry semantics

Review `SharesMediaSource.fetchItems` and cursor-store interaction:

1. Record a next cursor only after a page fetch succeeds.
2. Do not advance cursor state when the fetch throws or is cancelled.
3. Ensure a retry of a failed page uses the same cursor.
4. Ensure resetting one scope does not invalidate other scopes.
5. Preserve folder identity, sort key, sort order, and page-size scope isolation.
6. Confirm invalid or exhausted cursors return safe empty pages without corrupting neighboring scopes.

### Phase 5 — Add focused test doubles and tests

Add dedicated test files where appropriate:

- `Tests/FichierKitTests/MediaSourceItemSortComparatorTests.swift`
- `Tests/FichierKitTests/SharesCursorStoreTests.swift`
- `Tests/FichierKitTests/AMSMB2ClientDownloadTests.swift` or an equivalent test fixture that can exercise the retry/download path without requiring a live SMB server.

#### Comparator tests

Cover both ascending and descending ordering for:

- `.name`
- `.date`
- `.size`
- `.type`

For every sort key, verify:

- Folders always precede files.
- Ties resolve deterministically by name and then stable ID where applicable.
- Missing dates use the documented `.distantPast` behavior.
- Repeated sorting produces identical order.

#### Cursor-store tests

Cover:

- Initial page lookup.
- Recorded cursor hit.
- Cursor miss fallback.
- Exhausted scope behavior.
- Resetting one scope while another scope remains intact.
- LRU eviction of only the least-recently-used scope.
- Re-access preventing eviction.
- Safe behavior after an evicted scope is requested again.

#### Download tests

Verify that:

- A successful download replaces an existing destination only after completion.
- A failed first attempt preserves the existing destination.
- A failed final attempt preserves the existing destination.
- Cancellation preserves the existing destination.
- No temporary `.part` files remain after success, failure, or cancellation.
- Retry attempts use distinct temporary paths.
- Progress cancellation does not delete the previous destination.

Use dependency injection or a test seam around the SMB manager operation. Do not add network-dependent tests that require a real SMB server.

### Phase 6 — Validate both platforms

Run without committing:

1. FichierKit tests on an iOS simulator.
2. FichierKit tests on a tvOS simulator.
3. Fichier iOS integration build and tests.
4. FichierTV tvOS build and tests.
5. Swift 6 concurrency diagnostics.
6. SwiftLint, if configured.
7. `git diff --check`.
8. A targeted search for destructive writes to `localURL` before successful completion.
9. A targeted search confirming no global cursor purge remains.

## Acceptance Criteria

- `AMSMB2Client` never deletes an existing destination before a successful replacement is ready.
- Failed and cancelled retries remove only temporary files.
- `SharesCursorStore.resetScope` affects only the requested scope.
- Cursor memory is bounded through targeted LRU eviction.
- Failed or cancelled pages do not advance cursor state.
- Comparator, cursor-store, and concrete download retry behavior have direct tests.
- Existing range-download and pagination tests continue to pass.
- iOS and tvOS builds/tests pass.
- No force unwraps, `try!`, credential logs, or unrelated changes are introduced.
- All changes remain uncommitted for review.

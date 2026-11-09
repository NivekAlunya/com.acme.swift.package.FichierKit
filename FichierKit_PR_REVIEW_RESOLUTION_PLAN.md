# FichierKit PR Review Resolution Plan

## Objective

Resolve the confirmed review findings on `feature/ios-code-update` while preserving iOS and tvOS compatibility, strict Swift 6 concurrency, the `1 Definition = 1 File` convention, and the workspace no-commit rule.

## Review Findings

### Re-entrant `playbackRate` observers — confirmed

`AVPlayerEngine` and `TVVLCPlayerEngine` both mutate `playbackRate` from inside `didSet` while clamping. They also do not explicitly reject non-finite values such as `.nan` and `.infinity`.

### Full-file buffering in default SMB downloads — confirmed

The default `SMBClientProtocol.downloadFile` implementation calls `readFileData(..., maxBytes: nil)`, loading the complete remote file into memory before writing it. This can cause severe memory pressure for large videos or documents and prevents useful mid-transfer cancellation.

## Resolution Plan

### 1. Replace re-entrant playback-rate observers

Files:

- `Sources/FichierKit/Sources/AVPlayerEngine.swift`
- `Sources/FichierKit/Sources/TVVLCPlayerEngine.swift`

For each engine:

1. Add private backing storage initialized to `1.0`.
2. Replace the stored property with a computed property.
3. Ignore non-finite values with `guard newValue.isFinite else { return }`.
4. Clamp valid values to `0.25...4.0` and store the result.
5. Update the underlying player rate without mutating the public property from its own observer.
6. Preserve `@MainActor` isolation and the existing `PlayerEngine` API.

For `AVPlayerEngine`, update `AVPlayer.defaultRate` and update `AVPlayer.rate` when playing. For `TVVLCPlayerEngine`, update `mediaPlayer.rate` only under `#if canImport(VLCKit)`.

### 2. Stream the default SMB download in bounded chunks

File:

- `Sources/FichierKit/Protocols/SMBClientProtocol.swift`

Replace the full-buffer fallback with 1 MiB range streaming through `readMediaRange`:

1. Check cancellation before the size query and before every range request.
2. Use a fixed chunk size of `1_048_576` bytes.
3. Create a uniquely named `.part` file beside `localURL`.
4. Write each chunk incrementally using `FileHandle`.
5. For known sizes, request until exactly `total` bytes are written. An empty response before that point must fail rather than install a truncated file.
6. For unknown or zero sizes, request successive ranges until an empty `Data()` response; handle a zero-byte file without looping.
7. Report progress after each chunk and throw `CancellationError` when the callback returns `false`.
8. Close the handle before installation.
9. Install only the completed temporary file, using replacement when the destination exists and move when it does not.
10. Remove the temporary file on every error or cancellation path.
11. Keep `AMSMB2Client.downloadFile` unchanged.
12. Do not use `readFileData(..., maxBytes: nil)` in this default path.

The implementation must never overwrite an existing destination until the new download is complete, and must not install a known-size file when fewer bytes were received.

### 3. Add a range-only test double

Add:

- `Tests/FichierKitTests/RangeOnlyMockSMBClient.swift`

Define one `RangeOnlyMockSMBClient` that conforms to `SMBClientProtocol`, implements range reads and file-size queries, records requested offsets and lengths, and records any accidental `readFileData` call. Do not override `downloadFile`, so the protocol extension is tested directly. Keep the type `Sendable` and avoid force unwraps and `try!`.

### 4. Expand unit coverage

Update:

- `Tests/FichierKitTests/FichierKitTests.swift`

Add tests for:

- Multi-chunk downloads larger than 1 MiB.
- Bounded, monotonic range requests and progress.
- Byte-identical output.
- No `readFileData` usage.
- Zero-byte files.
- Mid-transfer cancellation with `CancellationError`.
- Cleanup of destination and `.part` files after failure or cancellation.
- Preservation of an existing destination after a failed replacement.
- Known-size early EOF failing without installing truncated output.
- Playback-rate clamping on both engines.
- Ignoring `.nan` and `.infinity` while preserving the previous valid rate.

Keep each helper type in its own file and use no force unwraps or `try!`.

### 5. Verify both platforms and downstream integration

Run without committing:

1. FichierKit tests on an iOS simulator.
2. FichierTV build and tests on a tvOS simulator.
3. Fichier iOS build and tests.
4. `swiftlint --strict` for the Fichier app if configured.
5. `git diff --check` in both repositories.
6. A review for new force unwraps, `try!`, actor-isolation warnings, and unintended API changes.

## Acceptance Criteria

- No playback-rate setter mutates itself through a property observer.
- Non-finite playback rates are ignored.
- Default SMB downloads stream through bounded range requests instead of buffering the full file.
- Cancellation and failures leave no partial destination or `.part` file.
- Existing destination files remain intact if a replacement download fails.
- `AMSMB2Client.downloadFile` is unchanged.
- iOS and tvOS builds and relevant tests pass.
- Swift 6 concurrency diagnostics remain clean.
- `1 Definition = 1 File` and no-force-unwrap rules remain satisfied.
- All changes remain uncommitted for user review.

//
//  AMSMB2Client.swift
//  FichierKit
//
//

import Foundation
import AMSMB2
import Synchronization

/// Actor-isolated SMB2/3 network client powered by `AMSMB2`, serializing all `libsmb2` operations safely.
public actor AMSMB2Client: SMBClientProtocol {
    public let server: SavedSMBConnection
    private let password: String
    private let sessionFactory: @Sendable (SavedSMBConnection, String) throws -> any SMB2SessionProtocol
    private var manager: (any SMB2SessionProtocol)?
    private var connectedShare: String?
    private var directorySnapshot: AMSMB2DirectorySnapshot?
    private let operationLimiter = SMBVideoThumbnailLimiter(maxConcurrent: 1)

    public init(server: SavedSMBConnection, password: String) {
        self.server = server
        self.password = password
        self.sessionFactory = Self.defaultSessionFactory
    }

    init(
        server: SavedSMBConnection,
        password: String,
        sessionFactory: @escaping @Sendable (SavedSMBConnection, String) throws -> any SMB2SessionProtocol
    ) {
        self.server = server
        self.password = password
        self.sessionFactory = sessionFactory
    }

    /// Discovers non-hidden share volumes exported by the SMB server.
    public func listShares() async throws -> [String] {
        try await operationLimiter.withPermit {
            try await self.performListShares()
        }
    }

    /// Lists child folders and supported media files within the specified share and relative path.
    public func listDirectory(share: String, path: String) async throws -> [MediaSourceItem] {
        try await operationLimiter.withPermit {
            try await self.performListDirectory(share: share, path: path)
        }
    }

    /// Lists a bounded page of child folders and supported media files within the specified share and relative path.
    ///
    /// Because `AMSMB2.SMB2Manager.contentsOfDirectory(atPath:)` returns all directory entries in one snapshot and
    /// SMB2 lacks server-side sorting, the initial un-cursored fetch retrieves and classifies entries once,
    /// immediately drops raw filesystem dictionaries and unsupported extensions, caches one sorted directory index
    /// for subsequent cursored reads, and frees the index once exhausted, replaced, or disconnected.
    public func listDirectoryPage(
        share: String,
        path: String,
        cursor: String?,
        pageSize: Int,
        sortBy sortKey: MediaSortKey,
        order sortOrder: MediaSortOrder
    ) async throws -> SMBDirectoryPage {
        try await operationLimiter.withPermit {
            try await self.performListDirectoryPage(
                share: share,
                path: path,
                cursor: cursor,
                pageSize: pageSize,
                sortBy: sortKey,
                order: sortOrder
            )
        }
    }

    /// Reads complete file contents or a prefix up to `maxBytes` from the remote SMB share.
    public func readFileData(share: String, path: String, maxBytes: Int64?) async throws -> Data {
        try await operationLimiter.withPermit {
            try await self.performReadFileData(share: share, path: path, maxBytes: maxBytes)
        }
    }

    /// Reads a byte range with automatic reconnect recovery for progressive media streaming.
    public func readMediaRange(share: String, path: String, offset: Int64, length: Int) async throws -> Data {
        guard length > 0 else { return Data() }
        return try await operationLimiter.withPermit {
            try await self.performReadMediaRange(share: share, path: path, offset: offset, length: length)
        }
    }

    /// Queries the byte size of an item on the remote share.
    public func fileSize(share: String, path: String) async throws -> Int64 {
        try await operationLimiter.withPermit {
            try await self.performFileSize(share: share, path: path)
        }
    }

    /// Streams a remote SMB file directly to a local file URL.
    public func downloadFile(
        share: String,
        path: String,
        to localURL: URL,
        progress: (@Sendable (Int64, Int64) -> Bool)?
    ) async throws {
        try await operationLimiter.withPermit {
            try await self.performDownloadFile(share: share, path: path, to: localURL, progress: progress)
        }
    }

    /// Creates a new directory at the specified path within a share.
    public func createDirectory(share: String, path: String) async throws {
        try await operationLimiter.withPermit {
            try await self.performCreateDirectory(share: share, path: path)
        }
    }

    /// Removes an item (file or directory) at the specified path within a share.
    public func removeItem(share: String, path: String) async throws {
        try await operationLimiter.withPermit {
            try await self.performRemoveItem(share: share, path: path)
        }
    }

    /// Moves or renames an item (file or directory) within a share from `fromPath` to `toPath`.
    public func moveItem(share: String, fromPath: String, toPath: String) async throws {
        try await operationLimiter.withPermit {
            try await self.performMoveItem(share: share, fromPath: fromPath, toPath: toPath)
        }
    }

    /// Disconnects the underlying SMB session cleanly and clears any cached directory index.
    ///
    /// Safe to call from a cancelled task; permit acquisition and disconnect complete idempotently.
    public func disconnect() async {
        await Task {
            try? await self.operationLimiter.withPermit {
                await self.performDisconnect()
            }
        }.value
    }

    // MARK: - Serialized SMB Implementations

    private func performListShares() async throws -> [String] {
        let maxAttempts = 3
        var lastError: Error?

        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                let mgr = try getOrCreateManager()
                let shareNames = try await mgr.listShareNames(enumerateHidden: false)
                connectedShare = nil
                return shareNames.sorted {
                    $0.localizedStandardCompare($1) == .orderedAscending
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                connectedShare = nil
                lastError = error

                if isConnectionResetError(error) {
                    try? await manager?.disconnectShare(gracefully: false)
                    manager = nil
                }

                if !isSpinUpOrTransientError(error) {
                    throw mapError(error, share: nil)
                }

                if attempt < maxAttempts {
                    let backoffSeconds = Double(attempt) * 1.5
                    let backoffNs = UInt64(backoffSeconds * 1_000_000_000)
                    try await Task.sleep(nanoseconds: backoffNs)
                }
            }
        }

        throw mapError(lastError ?? SMBError.unreachable(server.host), share: nil)
    }

    private func performListDirectory(share: String, path: String) async throws -> [MediaSourceItem] {
        try await fetchAndMapDirectoryEntries(share: share, normalizedPath: Self.normalizeRelativePath(path))
    }

    private func performListDirectoryPage(
        share: String,
        path: String,
        cursor: String?,
        pageSize: Int,
        sortBy sortKey: MediaSortKey,
        order sortOrder: MediaSortOrder
    ) async throws -> SMBDirectoryPage {
        try Task.checkCancellation()
        guard pageSize > 0 else {
            return SMBDirectoryPage(items: [], nextCursor: nil, totalCount: nil)
        }

        let normalizedPath = Self.normalizeRelativePath(path)
        let offset: Int
        if let cursor {
            guard let parsedOffset = Int(cursor), parsedOffset >= 0 else {
                return SMBDirectoryPage(items: [], nextCursor: nil, totalCount: nil)
            }
            offset = parsedOffset
        } else {
            offset = 0
            directorySnapshot = nil
        }

        let sortedItems: [MediaSourceItem]
        if let snapshot = directorySnapshot,
           cursor != nil,
           snapshot.share == share,
           snapshot.normalizedPath == normalizedPath,
           snapshot.sortKey == sortKey,
           snapshot.sortOrder == sortOrder {
            sortedItems = snapshot.items
        } else {
            directorySnapshot = nil
            let mapped = try await fetchAndMapDirectoryEntries(share: share, normalizedPath: normalizedPath)
            try Task.checkCancellation()
            sortedItems = MediaSourceItemSortComparator.sortFoldersFirst(
                mapped,
                sortBy: sortKey,
                order: sortOrder
            )
        }

        guard offset < sortedItems.count else {
            directorySnapshot = nil
            return SMBDirectoryPage(items: [], nextCursor: nil, totalCount: sortedItems.count)
        }

        let endIndex = min(offset + pageSize, sortedItems.count)
        let hasMore = endIndex < sortedItems.count
        if hasMore {
            directorySnapshot = AMSMB2DirectorySnapshot(
                share: share,
                normalizedPath: normalizedPath,
                sortKey: sortKey,
                sortOrder: sortOrder,
                items: sortedItems
            )
        } else {
            directorySnapshot = nil
        }

        return SMBDirectoryPage(
            items: Array(sortedItems[offset..<endIndex]),
            nextCursor: hasMore ? String(endIndex) : nil,
            totalCount: sortedItems.count
        )
    }

    private func fetchAndMapDirectoryEntries(share: String, normalizedPath: String) async throws -> [MediaSourceItem] {
        let maxAttempts = 4
        var lastError: Error?

        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                // On initial retry, preserve tree connection so spinning media is not disrupted.
                // Reconnect only after multiple failures or when socket is reset.
                let forceReconnect = attempt > 2 || (lastError != nil && isConnectionResetError(lastError!))
                let mgr = try await ensureConnected(to: share, forceReconnect: forceReconnect)
                try Task.checkCancellation()

                let entries = try await mgr.directoryEntries(atPath: normalizedPath)
                try Task.checkCancellation()

                var results: [MediaSourceItem] = []
                results.reserveCapacity(entries.count)

                for entry in entries {
                    if Task.isCancelled { throw CancellationError() }
                    guard let name = entry.name,
                          !name.hasPrefix(".") else {
                        continue
                    }

                    let entryPath = entry.path
                        ?? (normalizedPath.isEmpty ? name : "\(normalizedPath)/\(name)")
                    let cleanRelativePath = Self.normalizeRelativePath(entryPath)
                    let modifiedDate = entry.modifiedDate
                    let fullPath = cleanRelativePath.isEmpty ? share : "\(share)/\(cleanRelativePath)"
                    let itemID = "\(server.id)|\(share)::/\(cleanRelativePath)"

                    if entry.isDirectory {
                        results.append(
                            MediaSourceItem(
                                id: itemID,
                                name: name,
                                path: fullPath,
                                type: .folder,
                                size: 0,
                                modifiedDate: modifiedDate,
                                sourceID: server.id,
                                smbShare: share,
                                smbPath: cleanRelativePath
                            )
                        )
                    } else if entry.isRegularFile {
                        let ext = (name as NSString).pathExtension.lowercased()
                        guard SupportedMediaTypes.isSupported(extension: ext) else {
                            continue
                        }
                        let itemType: MediaItemType
                        if SupportedMediaTypes.isVideo(extension: ext) {
                            itemType = .video
                        } else {
                            #if !os(tvOS)
                            itemType = SupportedMediaTypes.isDocument(extension: ext) ? .document : .image
                            #else
                            itemType = .image
                            #endif
                        }
                        results.append(
                            MediaSourceItem(
                                id: itemID,
                                name: name,
                                path: fullPath,
                                type: itemType,
                                size: entry.fileSize,
                                modifiedDate: modifiedDate,
                                sourceID: server.id,
                                smbShare: share,
                                smbPath: cleanRelativePath
                            )
                        )
                    }
                }

                return results
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                directorySnapshot = nil
                lastError = error

                if isConnectionResetError(error) {
                    connectedShare = nil
                    try? await manager?.disconnectShare(gracefully: false)
                    manager = nil
                }

                if !isSpinUpOrTransientError(error) {
                    connectedShare = nil
                    throw mapError(error, share: share)
                }

                if attempt < maxAttempts {
                    // Escalating backoff for spinning mechanical drive wake-up (1.5s, 3.0s, 4.5s)
                    let backoffSeconds = Double(attempt) * 1.5
                    let backoffNs = UInt64(backoffSeconds * 1_000_000_000)
                    try await Task.sleep(nanoseconds: backoffNs)
                } else {
                    connectedShare = nil
                }
            }
        }

        throw mapError(lastError ?? SMBError.unreachable(server.host), share: share)
    }

    private func performReadFileData(share: String, path: String, maxBytes: Int64?) async throws -> Data {
        let maxAttempts = 4
        var lastError: Error?
        let normalizedPath = Self.normalizeRelativePath(path)

        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                let forceReconnect = attempt > 2 || (lastError != nil && isConnectionResetError(lastError!))
                let mgr = try await ensureConnected(to: share, forceReconnect: forceReconnect)
                try Task.checkCancellation()

                if let maxBytes, maxBytes > 0 {
                    let range: Range<Int64> = 0..<maxBytes
                    return try await mgr.readContents(atPath: normalizedPath, range: range) { _, _ in
                        !Task.isCancelled
                    }
                } else {
                    return try await mgr.readContents(atPath: normalizedPath, range: nil) { _, _ in
                        !Task.isCancelled
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                lastError = error

                if isConnectionResetError(error) {
                    connectedShare = nil
                    try? await manager?.disconnectShare(gracefully: false)
                    manager = nil
                }

                if !isSpinUpOrTransientError(error) {
                    connectedShare = nil
                    throw mapError(error, share: share)
                }

                if attempt < maxAttempts {
                    let backoffSeconds = Double(attempt) * 1.5
                    let backoffNs = UInt64(backoffSeconds * 1_000_000_000)
                    try await Task.sleep(nanoseconds: backoffNs)
                } else {
                    connectedShare = nil
                }
            }
        }

        throw mapError(lastError ?? SMBError.unreachable(server.host), share: share)
    }

    private func performReadMediaRange(share: String, path: String, offset: Int64, length: Int) async throws -> Data {
        let maxAttempts = 3
        var lastError: Error?
        let normalizedPath = Self.normalizeRelativePath(path)

        // Retry with linear backoff. Retries force a full reconnect when connection is dropped or on attempt > 2.
        // Cancellation is never retried and is always rethrown as `CancellationError`.
        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                let forceReconnect = attempt > 2 || (lastError != nil && isConnectionResetError(lastError!))
                let mgr = try await ensureConnected(to: share, forceReconnect: forceReconnect)
                try Task.checkCancellation()

                let end = offset + Int64(length)
                let range: Range<Int64> = offset..<end
                // The progress closure is the only hook libsmb2 offers to abort a read in flight:
                // returning `false` stops the transfer when the Swift task is cancelled.
                return try await mgr.readContents(atPath: normalizedPath, range: range) { _, _ in
                    !Task.isCancelled
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                lastError = error

                if isConnectionResetError(error) {
                    connectedShare = nil
                    try? await manager?.disconnectShare(gracefully: false)
                    manager = nil
                }

                if !isSpinUpOrTransientError(error) {
                    connectedShare = nil
                    throw mapError(error, share: share)
                }

                if attempt < maxAttempts {
                    let backoffSeconds = Double(attempt) * 1.0
                    let backoffNs = UInt64(backoffSeconds * 1_000_000_000)
                    try await Task.sleep(nanoseconds: backoffNs)
                } else {
                    connectedShare = nil
                }
            }
        }

        throw mapError(lastError ?? SMBError.unreachable(server.host), share: share)
    }

    private func performFileSize(share: String, path: String) async throws -> Int64 {
        let maxAttempts = 3
        var lastError: Error?
        let normalizedPath = Self.normalizeRelativePath(path)

        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                let forceReconnect = attempt > 2 || (lastError != nil && isConnectionResetError(lastError!))
                let mgr = try await ensureConnected(to: share, forceReconnect: forceReconnect)
                return try await mgr.fileSize(atPath: normalizedPath)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                lastError = error

                if isConnectionResetError(error) {
                    connectedShare = nil
                    try? await manager?.disconnectShare(gracefully: false)
                    manager = nil
                }

                if !isSpinUpOrTransientError(error) {
                    connectedShare = nil
                    throw mapError(error, share: share)
                }

                if attempt < maxAttempts {
                    let backoffSeconds = Double(attempt) * 1.0
                    let backoffNs = UInt64(backoffSeconds * 1_000_000_000)
                    try await Task.sleep(nanoseconds: backoffNs)
                } else {
                    connectedShare = nil
                }
            }
        }

        throw mapError(lastError ?? SMBError.unreachable(server.host), share: share)
    }

    private func performDownloadFile(
        share: String,
        path: String,
        to localURL: URL,
        progress: (@Sendable (Int64, Int64) -> Bool)?
    ) async throws {
        let maxAttempts = 3
        var lastError: Error?
        let normalizedPath = Self.normalizeRelativePath(path)
        let directoryURL = localURL.deletingLastPathComponent()

        // Each attempt downloads into a unique `.part` file next to the destination and is only moved
        // into place on success (`installCompletedFile`), so a failed or cancelled download can never
        // leave a truncated file that later looks like a valid cache entry.
        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            let tempURL = directoryURL.appendingPathComponent(
                "\(localURL.lastPathComponent).\(UUID().uuidString).part"
            )

            do {
                let forceReconnect = attempt > 2 || (lastError != nil && isConnectionResetError(lastError!))
                try await performSingleDownloadAttempt(
                    share: share,
                    normalizedPath: normalizedPath,
                    tempURL: tempURL,
                    destinationURL: localURL,
                    forceReconnect: forceReconnect,
                    progress: progress
                )
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                // libsmb2 reports an aborted transfer (progress callback returned false) as ECANCELED.
                if let posix = error as? POSIXError, posix.code == .ECANCELED {
                    throw CancellationError()
                }
                lastError = error

                if isConnectionResetError(error) {
                    connectedShare = nil
                    try? await manager?.disconnectShare(gracefully: false)
                    manager = nil
                }

                if !isSpinUpOrTransientError(error) {
                    connectedShare = nil
                    throw mapError(error, share: share)
                }

                if attempt < maxAttempts {
                    let backoffSeconds = Double(attempt) * 1.0
                    let backoffNs = UInt64(backoffSeconds * 1_000_000_000)
                    try await Task.sleep(nanoseconds: backoffNs)
                } else {
                    connectedShare = nil
                }
            }
        }

        throw mapError(lastError ?? SMBError.unreachable(server.host), share: share)
    }

    private func performSingleDownloadAttempt(
        share: String,
        normalizedPath: String,
        tempURL: URL,
        destinationURL: URL,
        forceReconnect: Bool,
        progress: (@Sendable (Int64, Int64) -> Bool)?
    ) async throws {
        var shouldCleanupTempFile = true
        defer {
            if shouldCleanupTempFile {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }

        // libsmb2 invokes the progress closure on its own thread and surfaces an abort only as a
        // generic error. This flag records that *we* requested the abort so it can be reported as
        // `CancellationError` instead of a retryable network failure. `Mutex` guards cross-thread access.
        let cancelledByProgress = Mutex(false)
        let mgr = try await ensureConnected(to: share, forceReconnect: forceReconnect)
        try Task.checkCancellation()

        do {
            try await mgr.downloadItem(atPath: normalizedPath, to: tempURL) { bytes, total in
                if Task.isCancelled {
                    cancelledByProgress.withLock { $0 = true }
                    return false
                }
                let shouldContinue = progress?(bytes, total) ?? true
                if !shouldContinue {
                    cancelledByProgress.withLock { $0 = true }
                }
                return shouldContinue
            }
        } catch {
            if Task.isCancelled || cancelledByProgress.withLock({ $0 }) {
                throw CancellationError()
            }
            throw error
        }

        if Task.isCancelled || cancelledByProgress.withLock({ $0 }) {
            throw CancellationError()
        }

        try Self.installCompletedFile(from: tempURL, to: destinationURL)
        shouldCleanupTempFile = false
    }

    private static func validatePathComponents(_ path: String) throws {
        let components = path.split(separator: "/")
        for component in components {
            let str = String(component).trimmingCharacters(in: .whitespacesAndNewlines)
            if str.isEmpty || str == "." || str == ".." || str.contains(":") {
                throw FileOperationError.invalidName(String(component))
            }
        }
    }

    private static func isPermanentFilesystemError(_ error: Error) -> Bool {
        if let posix = error as? POSIXError {
            switch posix.code {
            case .ENOENT, .EACCES, .EPERM, .EEXIST, .ENOTDIR, .EISDIR, .EINVAL, .ENOTEMPTY:
                return true
            default:
                return false
            }
        }
        return false
    }

    private func performCreateDirectory(share: String, path: String) async throws {
        let normalized = Self.normalizeRelativePath(path)
        guard !normalized.isEmpty else {
            throw FileOperationError.invalidName(path)
        }
        try Self.validatePathComponents(normalized)
        let components = normalized.split(separator: "/")

        let maxAttempts = 2
        var lastError: Error?

        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                let mgr = try await ensureConnected(to: share, forceReconnect: attempt > 1)
                try Task.checkCancellation()
                try await mgr.createDirectory(atPath: normalized)
                directorySnapshot = nil
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch let fileOp as FileOperationError {
                throw fileOp
            } catch {
                if Task.isCancelled { throw CancellationError() }
                if let posix = error as? POSIXError, posix.code == .EEXIST {
                    let folderName = String(components.last ?? "")
                    throw FileOperationError.itemAlreadyExists(folderName)
                }
                let desc = error.localizedDescription.lowercased()
                if desc.contains("exists") || desc.contains("already") {
                    let folderName = String(components.last ?? "")
                    throw FileOperationError.itemAlreadyExists(folderName)
                }
                if Self.isPermanentFilesystemError(error) {
                    throw mapError(error, share: share)
                }
                connectedShare = nil
                lastError = error
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }

        throw mapError(lastError ?? SMBError.unreachable(server.host), share: share)
    }

    private func performRemoveItem(share: String, path: String) async throws {
        let normalized = Self.normalizeRelativePath(path)
        guard !normalized.isEmpty else {
            throw FileOperationError.invalidName(path)
        }
        try Self.validatePathComponents(normalized)

        let maxAttempts = 2
        var lastError: Error?

        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                let mgr = try await ensureConnected(to: share, forceReconnect: attempt > 1)
                try Task.checkCancellation()
                try await mgr.removeItem(atPath: normalized)
                directorySnapshot = nil
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch let fileOp as FileOperationError {
                throw fileOp
            } catch {
                if Task.isCancelled { throw CancellationError() }
                if Self.isPermanentFilesystemError(error) {
                    throw mapError(error, share: share)
                }
                connectedShare = nil
                lastError = error
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }

        throw mapError(lastError ?? SMBError.unreachable(server.host), share: share)
    }

    private func performMoveItem(share: String, fromPath: String, toPath: String) async throws {
        let normFrom = Self.normalizeRelativePath(fromPath)
        let normTo = Self.normalizeRelativePath(toPath)
        guard !normFrom.isEmpty else {
            throw FileOperationError.invalidName(fromPath)
        }
        guard !normTo.isEmpty else {
            throw FileOperationError.invalidName(toPath)
        }
        try Self.validatePathComponents(normFrom)
        try Self.validatePathComponents(normTo)
        let toComponents = normTo.split(separator: "/")

        // Already in destination
        if normFrom == normTo {
            throw FileOperationError.alreadyInDestination
        }

        // Cannot move into self or child folder
        if normTo.hasPrefix(normFrom + "/") {
            throw FileOperationError.cannotMoveIntoSelf
        }

        let maxAttempts = 2
        var lastError: Error?

        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                let mgr = try await ensureConnected(to: share, forceReconnect: attempt > 1)
                try Task.checkCancellation()
                try await mgr.moveItem(atPath: normFrom, toPath: normTo)
                directorySnapshot = nil
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch let fileOp as FileOperationError {
                throw fileOp
            } catch {
                if Task.isCancelled { throw CancellationError() }
                if let posix = error as? POSIXError, posix.code == .EEXIST {
                    let itemName = String(toComponents.last ?? "")
                    throw FileOperationError.itemAlreadyExists(itemName)
                }
                let desc = error.localizedDescription.lowercased()
                if desc.contains("exists") || desc.contains("already") {
                    let itemName = String(toComponents.last ?? "")
                    throw FileOperationError.itemAlreadyExists(itemName)
                }
                if Self.isPermanentFilesystemError(error) {
                    throw mapError(error, share: share)
                }
                connectedShare = nil
                lastError = error
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }

        throw mapError(lastError ?? SMBError.unreachable(server.host), share: share)
    }

    private func performDisconnect() async {
        try? await manager?.disconnectShare(gracefully: true)
        manager = nil
        connectedShare = nil
        directorySnapshot = nil
    }

    // MARK: - Private Helpers

    private func getOrCreateManager() throws -> any SMB2SessionProtocol {
        if let existing = manager {
            return existing
        }
        let created = try sessionFactory(server, password)
        self.manager = created
        return created
    }

    private func ensureConnected(to share: String, forceReconnect: Bool) async throws -> any SMB2SessionProtocol {
        let mgr = try getOrCreateManager()
        if forceReconnect || connectedShare != share {
            if forceReconnect {
                try? await mgr.disconnectShare(gracefully: true)
                connectedShare = nil
            }
            try await mgr.connectShare(name: share)
            connectedShare = share
        }
        return mgr
    }

    private static let defaultSessionFactory: @Sendable (SavedSMBConnection, String) throws -> any SMB2SessionProtocol = { server, password in
        // Normalize user-entered hosts: strip whitespace and `smb://`, and drop an IPv6 zone id
        // (`%en0`), which libsmb2 cannot parse inside a URL.
        let cleanHost = server.host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "smb://", with: "")
            .components(separatedBy: "%").first ?? server.host

        guard let url = URL(string: "smb://\(cleanHost)") else {
            throw SMBError.unreachable(server.host)
        }

        let credential = URLCredential(
            user: server.username,
            password: password,
            persistence: .forSession
        )

        guard let created = SMB2Manager(url: url, credential: credential) else {
            throw SMBError.unreachable(server.host)
        }
        // Allow up to 60 seconds to accommodate idle/sleeping mechanical hard drives spinning up.
        created.timeout = 60.0
        return AMSMB2SessionAdapter(manager: created)
    }

    /// Determines whether an error indicates a severed connection, dropped socket, or reset session.
    private func isConnectionResetError(_ error: Error) -> Bool {
        if let posix = error as? POSIXError {
            switch posix.code {
            case .ECONNRESET, .ECONNABORTED, .ENOTCONN, .EPIPE, .ENETRESET, .ESHUTDOWN, .EHOSTDOWN, .EHOSTUNREACH, .ENETUNREACH:
                return true
            default:
                break
            }
        }
        let desc = error.localizedDescription.lowercased()
        if desc.contains("connection reset") ||
           desc.contains("broken pipe") ||
           desc.contains("not connected") ||
           desc.contains("status_connection_reset") ||
           desc.contains("status_connection_disconnected") ||
           desc.contains("status_network_name_deleted") ||
           desc.contains("status_user_session_deleted") ||
           desc.contains("0xc000020d") ||
           desc.contains("0xc000020c") ||
           desc.contains("0xc00000c9") ||
           desc.contains("0xc0000203") {
            return true
        }
        return false
    }

    /// Determines whether an SMB error is transient or caused by an idle drive spinning up,
    /// so the operation should be retried with escalating backoff before giving up.
    private func isSpinUpOrTransientError(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let smbError = error as? SMBError {
            switch smbError {
            case .timeout, .unreachable:
                return true
            case .badCredentials, .noShares, .shareNotFound:
                return false
            case .unknown(let desc):
                let lower = desc.lowercased()
                return Self.containsSpinUpKeyword(lower)
            }
        }
        if let posix = error as? POSIXError {
            switch posix.code {
            case .ETIMEDOUT, .EIO, .EAGAIN, .EBUSY, .EINTR:
                return true
            case .EACCES, .EPERM, .EAUTH, .ENOENT:
                return false
            default:
                break
            }
        }
        if isConnectionResetError(error) {
            return true
        }
        let desc = error.localizedDescription.lowercased()
        return Self.containsSpinUpKeyword(desc)
    }

    private static func containsSpinUpKeyword(_ desc: String) -> Bool {
        if desc.contains("query directory failed") { return true }
        if desc.contains("status_io_timeout") || desc.contains("0xc00000b5") || desc.contains("0x000000b5") { return true }
        if desc.contains("status_device_not_ready") || desc.contains("0xc00000a3") || desc.contains("0x000000a3") { return true }
        if desc.contains("status_device_busy") || desc.contains("0xc000009a") || desc.contains("0x0000009a") { return true }
        if desc.contains("status_device_off_line") { return true }
        if desc.contains("status_device_data_error") || desc.contains("0xc000009c") || desc.contains("0x0000009c") { return true }
        if desc.contains("status_logical_disk_error") || desc.contains("0xc00000b7") { return true }
        if desc.contains("timed out") || desc.contains("timeout") { return true }
        if desc.contains("not ready") || desc.contains("busy") || desc.contains("spin") { return true }
        if desc.contains("input/output error") || desc.contains("i/o error") { return true }
        return false
    }

    /// Atomically publishes a finished download. `replaceItemAt` swaps an existing file in one step,
    /// so concurrent readers never observe a partially written destination.
    private static func installCompletedFile(from tempURL: URL, to destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            _ = try FileManager.default.replaceItemAt(
                destinationURL,
                withItemAt: tempURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        }
    }

    private func mapError(_ error: Error, share: String?) -> SMBError {
        if let smbError = error as? SMBError {
            return smbError
        }
        if let posix = error as? POSIXError {
            switch posix.code {
            case .EACCES, .EPERM, .EAUTH:
                return .badCredentials
            case .ETIMEDOUT:
                return .timeout
            case .ECONNREFUSED, .EHOSTUNREACH, .ENETUNREACH, .ENOTCONN, .EHOSTDOWN:
                return .unreachable(server.host)
            case .ENOENT:
                if let share {
                    return .shareNotFound(share)
                }
                return .unknown(posix.localizedDescription)
            default:
                return .unknown(posix.localizedDescription)
            }
        }
        // Fallback heuristic: AMSMB2 surfaces some libsmb2 failures as plain `NSError`s with only a
        // localized message, so classify by keyword. Order matters ("timed out" before generic "connect").
        let desc = error.localizedDescription.lowercased()
        if desc.contains("auth") || desc.contains("logon") || desc.contains("credential") || desc.contains("permission") {
            return .badCredentials
        }
        if desc.contains("timed out") || desc.contains("timeout") || desc.contains("status_io_timeout") || desc.contains("0xc00000b5") {
            return .timeout
        }
        if desc.contains("connect") || desc.contains("unreachable") || desc.contains("refused") || desc.contains("host") {
            return .unreachable(server.host)
        }
        return .unknown(error.localizedDescription)
    }

    private static func normalizeRelativePath(_ path: String) -> String {
        var trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed == "." {
            trimmed = ""
        }
        return trimmed
    }
}

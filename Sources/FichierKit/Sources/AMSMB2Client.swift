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
            connectedShare = nil
            throw mapError(error, share: nil)
        }
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
        let maxAttempts = 2
        var lastError: Error?

        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                let mgr = try await ensureConnected(to: share, forceReconnect: attempt > 1)
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
                connectedShare = nil
                directorySnapshot = nil
                lastError = error
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
        }

        throw mapError(lastError ?? SMBError.unreachable(server.host), share: share)
    }

    private func performReadFileData(share: String, path: String, maxBytes: Int64?) async throws -> Data {
        let maxAttempts = 2
        var lastError: Error?
        let normalizedPath = Self.normalizeRelativePath(path)

        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                let mgr = try await ensureConnected(to: share, forceReconnect: attempt > 1)
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
                connectedShare = nil
                lastError = error
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }

        throw mapError(lastError ?? SMBError.unreachable(server.host), share: share)
    }

    private func performReadMediaRange(share: String, path: String, offset: Int64, length: Int) async throws -> Data {
        let maxAttempts = 3
        var lastError: Error?
        let normalizedPath = Self.normalizeRelativePath(path)

        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                let mgr = try await ensureConnected(to: share, forceReconnect: attempt > 1)
                try Task.checkCancellation()

                let end = offset + Int64(length)
                let range: Range<Int64> = offset..<end
                return try await mgr.readContents(atPath: normalizedPath, range: range) { _, _ in
                    !Task.isCancelled
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                connectedShare = nil
                lastError = error
                if attempt < maxAttempts {
                    let backoffNs = UInt64(attempt) * 250_000_000
                    try? await Task.sleep(nanoseconds: backoffNs)
                }
            }
        }

        throw mapError(lastError ?? SMBError.unreachable(server.host), share: share)
    }

    private func performFileSize(share: String, path: String) async throws -> Int64 {
        do {
            let mgr = try await ensureConnected(to: share, forceReconnect: false)
            let normalizedPath = Self.normalizeRelativePath(path)
            return try await mgr.fileSize(atPath: normalizedPath)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            connectedShare = nil
            throw mapError(error, share: share)
        }
    }

    private func performDownloadFile(
        share: String,
        path: String,
        to localURL: URL,
        progress: (@Sendable (Int64, Int64) -> Bool)?
    ) async throws {
        let maxAttempts = 2
        var lastError: Error?
        let normalizedPath = Self.normalizeRelativePath(path)
        let directoryURL = localURL.deletingLastPathComponent()

        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            let tempURL = directoryURL.appendingPathComponent(
                "\(localURL.lastPathComponent).\(UUID().uuidString).part"
            )

            do {
                try await performSingleDownloadAttempt(
                    share: share,
                    normalizedPath: normalizedPath,
                    tempURL: tempURL,
                    destinationURL: localURL,
                    forceReconnect: attempt > 1,
                    progress: progress
                )
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                if let posix = error as? POSIXError, posix.code == .ECANCELED {
                    throw CancellationError()
                }
                connectedShare = nil
                lastError = error
                if attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: 250_000_000)
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

        let cancelledByProgress = Mutex(false)
        let mgr = try await ensureConnected(to: share, forceReconnect: forceReconnect)
        try Task.checkCancellation()

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

        if Task.isCancelled || cancelledByProgress.withLock({ $0 }) {
            throw CancellationError()
        }

        try Self.installCompletedFile(from: tempURL, to: destinationURL)
        shouldCleanupTempFile = false
    }

    private func performDisconnect() async {
        try? await manager?.disconnectShare()
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
                try? await mgr.disconnectShare()
                connectedShare = nil
            }
            try await mgr.connectShare(name: share)
            connectedShare = share
        }
        return mgr
    }

    private static let defaultSessionFactory: @Sendable (SavedSMBConnection, String) throws -> any SMB2SessionProtocol = { server, password in
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
        created.timeout = 20.0
        return AMSMB2SessionAdapter(manager: created)
    }

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
        let desc = error.localizedDescription.lowercased()
        if desc.contains("auth") || desc.contains("logon") || desc.contains("credential") || desc.contains("permission") {
            return .badCredentials
        }
        if desc.contains("timed out") || desc.contains("timeout") {
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

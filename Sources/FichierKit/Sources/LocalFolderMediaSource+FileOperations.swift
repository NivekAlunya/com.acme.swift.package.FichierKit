//
//  LocalFolderMediaSource+FileOperations.swift
//  FichierKit
//

import Foundation

extension LocalFolderMediaSource {

    // MARK: - Headless File Management

    /// Creates a new subfolder in the specified parent folder or at the root directory.
    ///
    /// - Parameters:
    ///   - name: The user-specified folder name.
    ///   - parentFolder: Optional parent folder; defaults to root directory.
    /// - Returns: Newly created folder `MediaSourceItem`.
    /// - Throws: `FileOperationError` if the name is invalid or already exists.
    public func createFolder(
        named name: String,
        in parentFolder: MediaSourceItem? = nil
    ) async throws -> MediaSourceItem {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|\0").union(.controlCharacters)
        guard !trimmed.isEmpty,
              trimmed != ".",
              trimmed != "..",
              trimmed.rangeOfCharacter(from: invalidCharacters) == nil,
              !trimmed.hasSuffix(".") else {
            throw FileOperationError.invalidName(name)
        }

        let parentURL: URL
        if let parentFolder {
            parentURL = parentFolder.localURL ?? rootURL.appendingPathComponent(parentFolder.path, isDirectory: true)
        } else {
            parentURL = rootURL
        }
        let targetURL = parentURL.appendingPathComponent(trimmed, isDirectory: true).standardizedFileURL

        guard targetURL.deletingLastPathComponent().path == parentURL.standardizedFileURL.path else {
            throw FileOperationError.invalidName(name)
        }

        if fileManager.fileExists(atPath: targetURL.path) {
            throw FileOperationError.itemAlreadyExists(trimmed)
        }

        try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)

        let relativePath: String
        if let parentFolder {
            relativePath = parentFolder.path.isEmpty ? trimmed : "\(parentFolder.path)/\(trimmed)"
        } else {
            relativePath = trimmed
        }

        return MediaSourceItem(
            id: "\(id)::\(relativePath)",
            name: trimmed,
            path: relativePath,
            type: .folder,
            size: 0,
            modifiedDate: Date(),
            localURL: targetURL,
            sourceID: id
        )
    }

    /// Moves a collection of items or folders to the system Trash, falling back to permanent deletion if unsupported.
    ///
    /// - Parameter items: The collection of items to remove.
    /// - Throws: `FileOperationError` or filesystem errors.
    public func deleteItems(_ items: [MediaSourceItem]) async throws {
        for item in items {
            guard let url = item.localURL, fileManager.fileExists(atPath: url.path) else {
                throw FileOperationError.missingURL(item.name)
            }
        }

        for item in items {
            if let url = item.localURL {
                #if !os(tvOS)
                do {
                    try fileManager.trashItem(at: url, resultingItemURL: nil)
                } catch let error as CocoaError where error.code == .featureUnsupported {
                    try fileManager.removeItem(at: url)
                } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == 3328 {
                    try fileManager.removeItem(at: url)
                }
                #else
                try fileManager.removeItem(at: url)
                #endif
            }
        }
    }

    /// Moves items into a target destination folder.
    ///
    /// - Parameters:
    ///   - items: The items to move.
    ///   - destinationFolder: Destination directory item.
    /// - Throws: `FileOperationError` if validation fails or collisions occur.
    public func moveItems(_ items: [MediaSourceItem], to destinationFolder: MediaSourceItem) async throws {
        guard let destURL = destinationFolder.localURL else {
            throw FileOperationError.missingURL(destinationFolder.name)
        }

        let standardizedDestPath = destURL.standardizedFileURL.path
        var plannedMoves: [(sourceURL: URL, targetURL: URL)] = []
        var plannedTargets = Set<String>()

        for item in items {
            guard let sourceURL = item.localURL else {
                throw FileOperationError.missingURL(item.name)
            }

            let standardizedSourcePath = sourceURL.standardizedFileURL.path
            if item.type == .folder {
                if standardizedDestPath == standardizedSourcePath ||
                   standardizedDestPath.hasPrefix(standardizedSourcePath + "/") {
                    throw FileOperationError.cannotMoveIntoSelf
                }
            }

            let sourceParentPath = sourceURL.deletingLastPathComponent().standardizedFileURL.path
            if sourceParentPath == standardizedDestPath {
                continue
            }

            let targetURL = destURL.appendingPathComponent(
                sourceURL.lastPathComponent,
                isDirectory: item.type == .folder
            )
            let targetPath = targetURL.standardizedFileURL.path
            if fileManager.fileExists(atPath: targetPath) || plannedTargets.contains(targetPath) {
                throw FileOperationError.itemAlreadyExists(sourceURL.lastPathComponent)
            }
            plannedTargets.insert(targetPath)
            plannedMoves.append((sourceURL, targetURL))
        }

        for move in plannedMoves {
            try fileManager.moveItem(at: move.sourceURL, to: move.targetURL)
        }
    }

    /// Renames a media item or subfolder in-place, handling case-only renames on APFS filesystems.
    ///
    /// - Parameters:
    ///   - item: The target item to rename.
    ///   - newName: The new filename or directory name.
    /// - Returns: The updated `MediaSourceItem`.
    /// - Throws: `FileOperationError` if the name is invalid or a collision occurs.
    public func renameItem(_ item: MediaSourceItem, to newName: String) async throws -> MediaSourceItem {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|\0").union(.controlCharacters)
        guard !trimmed.isEmpty,
              trimmed != ".",
              trimmed != "..",
              trimmed.rangeOfCharacter(from: invalidCharacters) == nil,
              !trimmed.hasSuffix(".") else {
            throw FileOperationError.invalidName(newName)
        }

        if trimmed == item.name {
            return item
        }

        guard let sourceURL = item.localURL else {
            throw FileOperationError.missingURL(item.name)
        }

        let isDirectory = item.type == .folder
        let parentURL = sourceURL.deletingLastPathComponent().standardizedFileURL
        let targetURL = parentURL.appendingPathComponent(trimmed, isDirectory: isDirectory).standardizedFileURL

        guard targetURL.deletingLastPathComponent().path == parentURL.path else {
            throw FileOperationError.invalidName(newName)
        }

        let isCaseOnlyRename = sourceURL.path.caseInsensitiveCompare(targetURL.path) == .orderedSame
        if !isCaseOnlyRename && fileManager.fileExists(atPath: targetURL.path) {
            throw FileOperationError.itemAlreadyExists(trimmed)
        }

        if isCaseOnlyRename {
            let tempURL = parentURL.appendingPathComponent(".rename_\(UUID().uuidString).tmp", isDirectory: isDirectory)
            try fileManager.moveItem(at: sourceURL, to: tempURL)
            try fileManager.moveItem(at: tempURL, to: targetURL)
        } else {
            try fileManager.moveItem(at: sourceURL, to: targetURL)
        }

        let parentRelativePath = (item.path as NSString).deletingLastPathComponent
        let normalizedParent = (parentRelativePath == "." ? "" : parentRelativePath)
        let newRelativePath = normalizedParent.isEmpty ? trimmed : "\(normalizedParent)/\(trimmed)"

        return MediaSourceItem(
            id: "\(id)::\(newRelativePath)",
            name: trimmed,
            path: newRelativePath,
            type: item.type,
            size: item.size,
            modifiedDate: Date(),
            localURL: targetURL,
            sourceID: id
        )
    }
}

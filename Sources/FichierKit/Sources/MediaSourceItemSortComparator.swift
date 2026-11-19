//
//  MediaSourceItemSortComparator.swift
//  FichierKit
//
//

import Foundation

/// Deterministic folder-first comparator and sorter for `MediaSourceItem` collections.
public enum MediaSourceItemSortComparator: Sendable {
    /// Orders folders before files, sorting both groups according to `sortKey` and `sortOrder`.
    public static func sortFoldersFirst(
        _ items: [MediaSourceItem],
        sortBy sortKey: MediaSortKey,
        order sortOrder: MediaSortOrder,
        detailResolver: ((String) -> (resolution: Int?, duration: Double?))? = nil
    ) -> [MediaSourceItem] {
        var folders: [MediaSourceItem] = []
        var files: [MediaSourceItem] = []
        folders.reserveCapacity(items.count / 4)
        files.reserveCapacity(items.count)

        for item in items {
            if item.type == .folder {
                folders.append(item)
            } else {
                files.append(item)
            }
        }

        folders.sort { areInIncreasingOrder($0, $1, sortBy: sortKey, order: sortOrder, detailResolver: detailResolver) }
        files.sort { areInIncreasingOrder($0, $1, sortBy: sortKey, order: sortOrder, detailResolver: detailResolver) }
        return folders + files
    }

    /// Evaluates deterministic ordering between two items for `sortKey` and `sortOrder`.
    public static func areInIncreasingOrder(
        _ lhs: MediaSourceItem,
        _ rhs: MediaSourceItem,
        sortBy sortKey: MediaSortKey,
        order sortOrder: MediaSortOrder,
        detailResolver: ((String) -> (resolution: Int?, duration: Double?))? = nil
    ) -> Bool {
        let nameCompare = lhs.name.localizedStandardCompare(rhs.name)
        switch sortKey {
        case .name:
            if nameCompare == .orderedSame {
                return sortOrder == .ascending ? lhs.id < rhs.id : lhs.id > rhs.id
            }
            return sortOrder == .ascending ? nameCompare == .orderedAscending : nameCompare == .orderedDescending
        case .date:
            let lDate = lhs.modifiedDate ?? .distantPast
            let rDate = rhs.modifiedDate ?? .distantPast
            if lDate == rDate {
                if nameCompare == .orderedSame {
                    return lhs.id < rhs.id
                }
                return nameCompare == .orderedAscending
            }
            return sortOrder == .ascending ? lDate < rDate : lDate > rDate
        case .size:
            if lhs.size == rhs.size {
                if nameCompare == .orderedSame {
                    return lhs.id < rhs.id
                }
                return nameCompare == .orderedAscending
            }
            return sortOrder == .ascending ? lhs.size < rhs.size : lhs.size > rhs.size
        case .type:
            let lExt = (lhs.name as NSString).pathExtension
            let rExt = (rhs.name as NSString).pathExtension
            let extCompare = lExt.localizedStandardCompare(rExt)
            if extCompare == .orderedSame {
                if nameCompare == .orderedSame {
                    return sortOrder == .ascending ? lhs.id < rhs.id : lhs.id > rhs.id
                }
                return sortOrder == .ascending ? nameCompare == .orderedAscending : nameCompare == .orderedDescending
            }
            return sortOrder == .ascending ? extCompare == .orderedAscending : extCompare == .orderedDescending
        case .kind:
            let lRank = kindRank(for: lhs)
            let rRank = kindRank(for: rhs)
            if lRank == rRank {
                if nameCompare == .orderedSame {
                    return sortOrder == .ascending ? lhs.id < rhs.id : lhs.id > rhs.id
                }
                return sortOrder == .ascending ? nameCompare == .orderedAscending : nameCompare == .orderedDescending
            }
            return sortOrder == .ascending ? lRank < rRank : lRank > rRank
        case .resolution:
            let lRes = detailResolver?(lhs.id).resolution ?? 0
            let rRes = detailResolver?(rhs.id).resolution ?? 0
            if lRes <= 0 && rRes <= 0 {
                if nameCompare == .orderedSame {
                    return lhs.id < rhs.id
                }
                return nameCompare == .orderedAscending
            }
            if lRes <= 0 { return false }
            if rRes <= 0 { return true }
            if lRes == rRes {
                if nameCompare == .orderedSame {
                    return lhs.id < rhs.id
                }
                return nameCompare == .orderedAscending
            }
            return sortOrder == .ascending ? lRes < rRes : lRes > rRes
        case .duration:
            let lDur = detailResolver?(lhs.id).duration ?? 0
            let rDur = detailResolver?(rhs.id).duration ?? 0
            if lDur <= 0 && rDur <= 0 {
                if nameCompare == .orderedSame {
                    return lhs.id < rhs.id
                }
                return nameCompare == .orderedAscending
            }
            if lDur <= 0 { return false }
            if rDur <= 0 { return true }
            if lDur == rDur {
                if nameCompare == .orderedSame {
                    return lhs.id < rhs.id
                }
                return nameCompare == .orderedAscending
            }
            return sortOrder == .ascending ? lDur < rDur : lDur > rDur
        }
    }

    /// Numerical kind rank for grouping media by category:
    /// - 0: Images
    /// - 1: Videos
    /// - 2: Documents and PDFs
    /// - 3: Other
    private static func kindRank(for item: MediaSourceItem) -> Int {
        if item.type == .folder {
            return -1
        }
        let ext = (item.name as NSString).pathExtension.lowercased()
        if SupportedMediaTypes.isImage(extension: ext) {
            return 0
        }
        if SupportedMediaTypes.isVideo(extension: ext) {
            return 1
        }
        if SupportedMediaTypes.isDocument(extension: ext) || ext == "pdf" {
            return 2
        }
        return 3
    }
}

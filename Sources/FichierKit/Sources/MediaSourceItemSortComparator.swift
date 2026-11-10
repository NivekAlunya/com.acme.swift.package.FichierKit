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
        order sortOrder: MediaSortOrder
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

        folders.sort { areInIncreasingOrder($0, $1, sortBy: sortKey, order: sortOrder) }
        files.sort { areInIncreasingOrder($0, $1, sortBy: sortKey, order: sortOrder) }
        return folders + files
    }

    /// Evaluates deterministic ordering between two items for `sortKey` and `sortOrder`.
    public static func areInIncreasingOrder(
        _ lhs: MediaSourceItem,
        _ rhs: MediaSourceItem,
        sortBy sortKey: MediaSortKey,
        order sortOrder: MediaSortOrder
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
        }
    }
}

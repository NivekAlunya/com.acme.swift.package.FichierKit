//
//  MediaSourceItemSortComparatorTests.swift
//  FichierKitTests
//
//

import Foundation
import Testing
@testable import FichierKit

@Suite("MediaSourceItemSortComparator Tests")
struct MediaSourceItemSortComparatorTests {
    private static func makeItem(
        id: String,
        name: String,
        type: MediaItemType,
        size: Int64 = 0,
        modifiedDate: Date? = nil
    ) -> MediaSourceItem {
        MediaSourceItem(
            id: id,
            name: name,
            path: "Share/\(name)",
            type: type,
            size: size,
            modifiedDate: modifiedDate
        )
    }

    @Test("Name sorting keeps folders first, applies natural numeric ordering, and breaks ties deterministically")
    func testSortByNameAscendingAndDescending() {
        let folder10 = Self.makeItem(id: "d-10", name: "Album 10", type: .folder)
        let folder2 = Self.makeItem(id: "d-2", name: "Album 2", type: .folder)
        let folderTieA = Self.makeItem(id: "d-tie-a", name: "Archive", type: .folder)
        let folderTieB = Self.makeItem(id: "d-tie-b", name: "Archive", type: .folder)

        let file10 = Self.makeItem(id: "f-10", name: "Photo 10.jpg", type: .image, size: 10)
        let file2 = Self.makeItem(id: "f-2", name: "Photo 2.jpg", type: .image, size: 500)
        let fileTieA = Self.makeItem(id: "f-tie-a", name: "Same.png", type: .image)
        let fileTieB = Self.makeItem(id: "f-tie-b", name: "Same.png", type: .image)

        let unsorted = [file10, folderTieB, fileTieB, folder10, file2, folderTieA, fileTieA, folder2]

        let asc = MediaSourceItemSortComparator.sortFoldersFirst(unsorted, sortBy: .name, order: .ascending)
        #expect(asc.map(\.id) == [
            "d-2", "d-10", "d-tie-a", "d-tie-b",
            "f-2", "f-10", "f-tie-a", "f-tie-b"
        ])

        let desc = MediaSourceItemSortComparator.sortFoldersFirst(unsorted, sortBy: .name, order: .descending)
        #expect(desc.map(\.id) == [
            "d-tie-b", "d-tie-a", "d-10", "d-2",
            "f-tie-b", "f-tie-a", "f-10", "f-2"
        ])

        // Repeated and reversed invocations stay deterministic
        #expect(MediaSourceItemSortComparator.sortFoldersFirst(asc.reversed(), sortBy: .name, order: .ascending) == asc)
        #expect(MediaSourceItemSortComparator.sortFoldersFirst(desc.reversed(), sortBy: .name, order: .descending) == desc)
    }

    @Test("Date sorting places nil dates at distantPast and resolves ties by name then ID")
    func testSortByDateAscendingAndDescending() {
        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerDate = Date(timeIntervalSince1970: 1_750_000_000)

        let folderMissingDate = Self.makeItem(id: "d-nil", name: "Beta Folder", type: .folder, modifiedDate: nil)
        let folderDistantPast = Self.makeItem(
            id: "d-dp",
            name: "Alpha Folder",
            type: .folder,
            modifiedDate: .distantPast
        )
        let folderNew = Self.makeItem(id: "d-new", name: "New Folder", type: .folder, modifiedDate: newerDate)

        let fileNil = Self.makeItem(id: "f-nil", name: "00_missing.jpg", type: .image, modifiedDate: nil)
        let fileOldTieB = Self.makeItem(id: "f-old-b", name: "SameDate.jpg", type: .image, modifiedDate: olderDate)
        let fileOldTieA = Self.makeItem(id: "f-old-a", name: "SameDate.jpg", type: .image, modifiedDate: olderDate)
        let fileOldAlpha = Self.makeItem(id: "f-old-alpha", name: "Alpha.jpg", type: .image, modifiedDate: olderDate)
        let fileNew = Self.makeItem(id: "f-new", name: "Latest.mov", type: .video, modifiedDate: newerDate)

        let items = [fileNew, folderNew, fileOldTieB, fileNil, folderMissingDate, fileOldAlpha, folderDistantPast, fileOldTieA]

        let asc = MediaSourceItemSortComparator.sortFoldersFirst(items, sortBy: .date, order: .ascending)
        #expect(asc.map(\.id) == [
            "d-dp", "d-nil", "d-new",
            "f-nil", "f-old-alpha", "f-old-a", "f-old-b", "f-new"
        ])

        let desc = MediaSourceItemSortComparator.sortFoldersFirst(items, sortBy: .date, order: .descending)
        #expect(desc.map(\.id) == [
            "d-new", "d-dp", "d-nil",
            "f-new", "f-old-alpha", "f-old-a", "f-old-b", "f-nil"
        ])

        #expect(MediaSourceItemSortComparator.sortFoldersFirst(asc, sortBy: .date, order: .ascending) == asc)
        #expect(MediaSourceItemSortComparator.sortFoldersFirst(items.reversed(), sortBy: .date, order: .descending) == desc)
    }

    @Test("Size sorting keeps folders first and breaks size ties by name then ID")
    func testSortBySizeAscendingAndDescending() {
        let folderZ = Self.makeItem(id: "d-z", name: "Zeta", type: .folder, size: 0)
        let folderA = Self.makeItem(id: "d-a", name: "Alpha", type: .folder, size: 0)

        let tiny = Self.makeItem(id: "f-tiny", name: "tiny.jpg", type: .image, size: 100)
        let tieNameA = Self.makeItem(id: "f-tie-a", name: "Alpha.mp4", type: .video, size: 500)
        let tieSameB = Self.makeItem(id: "f-tie-b", name: "Beta.mp4", type: .video, size: 500)
        let tieSameB2 = Self.makeItem(id: "f-tie-b2", name: "Beta.mp4", type: .video, size: 500)
        let huge = Self.makeItem(id: "f-huge", name: "huge.mkv", type: .video, size: 9_999)

        let items = [huge, tieSameB2, folderZ, tiny, tieNameA, folderA, tieSameB]

        let asc = MediaSourceItemSortComparator.sortFoldersFirst(items, sortBy: .size, order: .ascending)
        #expect(asc.map(\.id) == [
            "d-a", "d-z",
            "f-tiny", "f-tie-a", "f-tie-b", "f-tie-b2", "f-huge"
        ])

        let desc = MediaSourceItemSortComparator.sortFoldersFirst(items, sortBy: .size, order: .descending)
        #expect(desc.map(\.id) == [
            "d-a", "d-z",
            "f-huge", "f-tie-a", "f-tie-b", "f-tie-b2", "f-tiny"
        ])

        #expect(MediaSourceItemSortComparator.sortFoldersFirst(asc.reversed(), sortBy: .size, order: .ascending) == asc)
        #expect(MediaSourceItemSortComparator.sortFoldersFirst(desc.reversed(), sortBy: .size, order: .descending) == desc)
    }

    @Test("Type sorting groups by extension deterministically in ascending and descending order")
    func testSortByTypeAscendingAndDescending() {
        let folderB = Self.makeItem(id: "d-b", name: "Folder.z", type: .folder)
        let folderA = Self.makeItem(id: "d-a", name: "Folder.a", type: .folder)

        let avif = Self.makeItem(id: "f-avif", name: "z.avif", type: .image)
        let jpgTie2 = Self.makeItem(id: "f-jpg-2", name: "Same.jpg", type: .image)
        let jpgTie1 = Self.makeItem(id: "f-jpg-1", name: "Same.jpg", type: .image)
        let jpgOther = Self.makeItem(id: "f-jpg-0", name: "Alpha.jpg", type: .image)
        let png = Self.makeItem(id: "f-png", name: "a.png", type: .image)

        let items = [png, folderB, jpgTie2, avif, jpgOther, folderA, jpgTie1]

        let asc = MediaSourceItemSortComparator.sortFoldersFirst(items, sortBy: .type, order: .ascending)
        #expect(asc.map(\.id) == [
            "d-a", "d-b",
            "f-avif", "f-jpg-0", "f-jpg-1", "f-jpg-2", "f-png"
        ])

        let desc = MediaSourceItemSortComparator.sortFoldersFirst(items, sortBy: .type, order: .descending)
        #expect(desc.map(\.id) == [
            "d-b", "d-a",
            "f-png", "f-jpg-2", "f-jpg-1", "f-jpg-0", "f-avif"
        ])

        #expect(MediaSourceItemSortComparator.sortFoldersFirst(items.reversed(), sortBy: .type, order: .ascending) == asc)
        #expect(MediaSourceItemSortComparator.sortFoldersFirst(desc, sortBy: .type, order: .descending) == desc)
    }

    @Test("Kind sorting groups by category (Images, Videos, Documents) keeping folders first")
    func testSortByKindAscendingAndDescending() {
        let folder = Self.makeItem(id: "d-1", name: "Folder", type: .folder)
        let pdf = Self.makeItem(id: "f-doc", name: "manual.pdf", type: .image)
        let video = Self.makeItem(id: "f-vid", name: "clip.mp4", type: .video)
        let image = Self.makeItem(id: "f-img", name: "photo.jpg", type: .image)

        let items = [pdf, folder, video, image]

        let asc = MediaSourceItemSortComparator.sortFoldersFirst(items, sortBy: .kind, order: .ascending)
        #expect(asc.map(\.id) == ["d-1", "f-img", "f-vid", "f-doc"])

        let desc = MediaSourceItemSortComparator.sortFoldersFirst(items, sortBy: .kind, order: .descending)
        #expect(desc.map(\.id) == ["d-1", "f-doc", "f-vid", "f-img"])
    }

    @Test("Resolution sorting orders by total pixel count")
    func testSortByResolutionAscendingAndDescending() {
        let folder = Self.makeItem(id: "d-1", name: "Folder", type: .folder)
        let hd = Self.makeItem(id: "f-hd", name: "hd.jpg", type: .image)
        let fourK = Self.makeItem(id: "f-4k", name: "4k.jpg", type: .image)
        let unk = Self.makeItem(id: "f-unk", name: "unknown.jpg", type: .image)
        let zero = Self.makeItem(id: "f-zero", name: "zero.jpg", type: .image)

        let resolver: (String) -> (resolution: Int?, duration: Double?) = { id in
            switch id {
            case "f-hd": return (1920 * 1080, nil)
            case "f-4k": return (3840 * 2160, nil)
            case "f-zero": return (0, nil)
            default: return (nil, nil)
            }
        }

        let items = [hd, folder, unk, fourK, zero]

        let asc = MediaSourceItemSortComparator.sortFoldersFirst(items, sortBy: .resolution, order: .ascending, detailResolver: resolver)
        #expect(asc.map(\.id) == ["d-1", "f-hd", "f-4k", "f-unk", "f-zero"])

        let desc = MediaSourceItemSortComparator.sortFoldersFirst(items, sortBy: .resolution, order: .descending, detailResolver: resolver)
        #expect(desc.map(\.id) == ["d-1", "f-4k", "f-hd", "f-unk", "f-zero"])
    }

    @Test("Duration sorting orders by playback duration in seconds")
    func testSortByDurationAscendingAndDescending() {
        let folder = Self.makeItem(id: "d-1", name: "Folder", type: .folder)
        let shortVid = Self.makeItem(id: "f-short", name: "short.mp4", type: .video)
        let longVid = Self.makeItem(id: "f-long", name: "long.mov", type: .video)
        let image = Self.makeItem(id: "f-img", name: "photo.png", type: .image)
        let zeroVid = Self.makeItem(id: "f-zero", name: "zero.mp4", type: .video)

        let resolver: (String) -> (resolution: Int?, duration: Double?) = { id in
            switch id {
            case "f-short": return (nil, 30.0)
            case "f-long": return (nil, 120.0)
            case "f-zero": return (nil, 0.0)
            default: return (nil, nil)
            }
        }

        let items = [longVid, folder, image, zeroVid, shortVid]

        let asc = MediaSourceItemSortComparator.sortFoldersFirst(items, sortBy: .duration, order: .ascending, detailResolver: resolver)
        #expect(asc.map(\.id) == ["d-1", "f-short", "f-long", "f-img", "f-zero"])

        let desc = MediaSourceItemSortComparator.sortFoldersFirst(items, sortBy: .duration, order: .descending, detailResolver: resolver)
        #expect(desc.map(\.id) == ["d-1", "f-long", "f-short", "f-img", "f-zero"])
    }
}

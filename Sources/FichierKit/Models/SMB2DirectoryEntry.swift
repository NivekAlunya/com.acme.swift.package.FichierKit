//
//  SMB2DirectoryEntry.swift
//  FichierKit
//
//

import Foundation

/// Sendable representation of a raw directory entry returned by an SMB2 session.
struct SMB2DirectoryEntry: Sendable {
    let name: String?
    let path: String?
    let isDirectory: Bool
    let isRegularFile: Bool
    let fileSize: Int64
    let modifiedDate: Date?
}

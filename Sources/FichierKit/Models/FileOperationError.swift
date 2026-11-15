//
//  FileOperationError.swift
//  FichierKit
//

import Foundation

/// Errors that can occur during file management operations such as creation, deletion, or moving.
public enum FileOperationError: LocalizedError, Sendable {
    case invalidName(String)
    case itemAlreadyExists(String)
    case cannotMoveIntoSelf
    case alreadyInDestination
    case missingURL(String)
    case unsupportedStorage
    case underlying(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidName(let name):
            return String(localized: "The folder name '\(name)' is invalid. Names cannot be empty or contain slashes.", comment: "Error message for invalid folder name")
        case .itemAlreadyExists(let name):
            return String(localized: "An item named '\(name)' already exists in this folder.", comment: "Error message when item already exists")
        case .cannotMoveIntoSelf:
            return String(localized: "Cannot move a folder into itself or one of its subfolders.", comment: "Error message when moving folder into itself")
        case .alreadyInDestination:
            return String(localized: "The item is already in the selected destination folder.", comment: "Error message when moving item to same folder")
        case .missingURL(let name):
            return String(localized: "Cannot locate '\(name)' on disk.", comment: "Error message when URL is missing")
        case .unsupportedStorage:
            return String(localized: "File management operations are currently supported on Local and iCloud Drive folders.", comment: "Error message when storage backend is not supported")
        case .underlying(let message):
            return message
        }
    }
}

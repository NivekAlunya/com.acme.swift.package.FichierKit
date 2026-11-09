//
//  PhotosAuthorizationStatus.swift
//  FichierKit
//

import Foundation

/// Represents the permission state of access to the system PhotoKit library.
public enum PhotosAuthorizationStatus: Sendable, Hashable, Equatable {
    case notDetermined
    case restricted
    case denied
    case authorized
    case limited
}

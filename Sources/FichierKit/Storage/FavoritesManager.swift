//
//  FavoritesManager.swift
//  FichierKit
//

import Foundation
import Observation
import os

/// Centralized state manager tracking user-favorited media item identifiers across all storage backends.
///
/// ### Architecture & Concurrency
/// - **Actor Isolation**: `@Observable @MainActor public final class`, synchronizing UI favorite states with views directly.
/// - **Persistence**: Stores identifiers as a serialized JSON `Set<String>` in `UserDefaults` for instant startup access.
@Observable
@MainActor
public final class FavoritesManager {
    
    /// Global shared singleton instance.
    public static let shared = FavoritesManager()
    
    /// The live set of favorited item identifiers.
    public private(set) var favoriteIDs: Set<String> = []
    
    /// Key used for serializing favorites to `UserDefaults`.
    private let storageKey = "SMBUserFavoriteItemIDs_v1"
    
    /// Private initializer restoring previously persisted favorites from `UserDefaults`.
    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey) {
            do {
                self.favoriteIDs = try JSONDecoder().decode(Set<String>.self, from: data)
            } catch {
                FichierKitLog.favoritesManager.error("Failed to decode favorites from storage: \(error.localizedDescription, privacy: .private)")
            }
        }
    }
    
    /// Checks whether the specified item ID is currently marked as a favorite.
    ///
    /// - Parameter id: The unique identifier to test.
    /// - Returns: `true` if favorited; `false` otherwise.
    public func isFavorite(id: String) -> Bool {
        favoriteIDs.contains(id)
    }
    
    /// Toggles the favorite status for a given identifier and immediately persists the update.
    ///
    /// - Parameter id: The unique item identifier to toggle.
    /// - Returns: `true` if the item is now favorited, `false` if it was unfavorited.
    @discardableResult
    public func toggleFavorite(id: String) -> Bool {
        let isNowFavorite: Bool
        if favoriteIDs.contains(id) {
            favoriteIDs.remove(id)
            isNowFavorite = false
        } else {
            favoriteIDs.insert(id)
            isNowFavorite = true
        }
        save()
        return isNowFavorite
    }
    
    /// Persists the updated favorite identifiers set into `UserDefaults`.
    private func save() {
        do {
            let encoded = try JSONEncoder().encode(favoriteIDs)
            UserDefaults.standard.set(encoded, forKey: storageKey)
        } catch {
            FichierKitLog.favoritesManager.error("Failed to encode favorites: \(error.localizedDescription, privacy: .private)")
        }
    }
}

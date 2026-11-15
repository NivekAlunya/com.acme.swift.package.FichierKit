//
//  ThreadSafeMemoryCache.swift
//  FichierKit
//

import Foundation

/// A high-performance, `@unchecked Sendable` generic in-memory cache wrapper around Apple's foundation `NSCache`.
///
/// ### Concurrency Architecture
/// Apple's `NSCache` is thread-safe according to official documentation:
/// *"You can add, remove, and query items in the cache from different threads without having to lock the cache yourself."*
/// However, because `NSCache` is an Objective-C class not yet marked `Sendable` in standard library overlays,
/// this wrapper satisfies Swift 6 strict concurrency checks without resorting to `nonisolated(unsafe)`.
nonisolated public final class ThreadSafeMemoryCache<Key: AnyObject, Value: AnyObject>: @unchecked Sendable {
    
    /// Underlying system `NSCache` managing LRU eviction and memory pressure purges.
    private let cache = NSCache<Key, Value>()
    
    /// Initializes a memory cache with optional entry count and cost constraints.
    ///
    /// - Parameters:
    ///   - countLimit: Maximum number of objects allowed before LRU eviction occurs. `0` indicates no count limit.
    ///   - totalCostLimit: Maximum aggregate cost threshold in bytes. `0` indicates no cost limit.
    public init(countLimit: Int = 0, totalCostLimit: Int = 0) {
        if countLimit > 0 {
            cache.countLimit = countLimit
        }
        if totalCostLimit > 0 {
            cache.totalCostLimit = totalCostLimit
        }
    }
    
    /// Retrieves a cached value for the specified key.
    ///
    /// - Parameter key: The lookup key object.
    /// - Returns: The cached value, or `nil` if purged or never stored.
    public func object(forKey key: Key) -> Value? {
        cache.object(forKey: key)
    }
    
    /// Caches a value for the specified key without explicit cost weighting.
    ///
    /// - Parameters:
    ///   - obj: The object to retain in cache.
    ///   - key: The key associated with the object.
    public func setObject(_ obj: Value, forKey key: Key) {
        cache.setObject(obj, forKey: key)
    }
    
    /// Caches a value for the specified key with an associated memory cost (e.g. byte length or pixel count).
    ///
    /// - Parameters:
    ///   - obj: The object to retain in cache.
    ///   - key: The key associated with the object.
    ///   - cost: The estimated memory cost used for capacity evaluation.
    public func setObject(_ obj: Value, forKey key: Key, cost: Int) {
        cache.setObject(obj, forKey: key, cost: cost)
    }
    
    /// Evicts a specific cached value associated with the specified key.
    ///
    /// - Parameter key: The key to remove.
    public func removeObject(forKey key: Key) {
        cache.removeObject(forKey: key)
    }
    
    /// Clears all stored objects from the cache synchronously.
    public func removeAllObjects() {
        cache.removeAllObjects()
    }
}

//
//  SMBPasswordStoreTests.swift
//  FichierKitTests
//

import Foundation
import Security
import Testing
@testable import FichierKit

@Suite("SMBPasswordStore Tests")
struct SMBPasswordStoreTests {
    @Test("Save throws on device when Keychain write fails and does not keep in-memory fallback")
    func deviceThrowsOnKeychainWriteFailure() async {
        let backend = MockKeychainCredentialBackend(
            updateStatus: errSecItemNotFound,
            addStatus: errSecAuthFailed,
            copyStatus: errSecItemNotFound
        )

        let store = SMBPasswordStore(
            service: "test.smb.device",
            allowInMemoryFallback: false,
            backend: backend
        )

        await #expect(throws: SMBPasswordStoreError.keychainWriteFailed(status: errSecAuthFailed)) {
            try await store.savePassword("secret", for: "user@nas")
        }

        let loaded = await store.loadPassword(for: "user@nas")
        #expect(loaded == nil)
    }

    @Test("Save falls back to memory in simulator/test mode when Keychain is unavailable")
    func simulatorFallsBackToMemory() async throws {
        let backend = MockKeychainCredentialBackend(
            updateStatus: errSecItemNotFound,
            addStatus: errSecMissingEntitlement,
            copyStatus: errSecMissingEntitlement
        )

        let store = SMBPasswordStore(
            service: "test.smb.sim",
            allowInMemoryFallback: true,
            backend: backend
        )

        try await store.savePassword("secret", for: "user@nas")
        let loaded = await store.loadPassword(for: "user@nas")
        #expect(loaded == "secret")
    }

    @Test("Save persists via Keychain backend when SecItemAdd succeeds")
    func saveSucceedsViaKeychainBackend() async throws {
        let backend = MockKeychainCredentialBackend(
            updateStatus: errSecItemNotFound,
            addStatus: errSecSuccess,
            copyStatus: errSecSuccess
        )

        let store = SMBPasswordStore(
            service: "test.smb.success",
            allowInMemoryFallback: false,
            backend: backend
        )

        try await store.savePassword("secret", for: "user@nas")
        let loaded = await store.loadPassword(for: "user@nas")
        #expect(loaded == "secret")
    }
}

//
//  FichierThemeTests.swift
//  FichierKitTests
//

import SwiftUI
import Testing
#if canImport(UIKit)
import UIKit
#endif
@testable import FichierKit

@Suite("FichierTheme Brand Colors")
struct FichierThemeTests {
    @Test("Brand semantic colors are distinct")
    func brandColorsAreDistinct() {
        #expect(FichierTheme.accent != FichierTheme.connected)
        #expect(FichierTheme.accent != FichierTheme.attention)
        #expect(FichierTheme.connected != FichierTheme.attention)
    }

    #if canImport(UIKit)
    @Test("Brand semantic colors adapt between light and dark appearances")
    func brandColorsAdaptForLightAndDarkTraits() {
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

        let lightAccent = UIColor(FichierTheme.accent).resolvedColor(with: lightTraits)
        let darkAccent = UIColor(FichierTheme.accent).resolvedColor(with: darkTraits)
        #expect(lightAccent != darkAccent)

        let lightConnected = UIColor(FichierTheme.connected).resolvedColor(with: lightTraits)
        let darkConnected = UIColor(FichierTheme.connected).resolvedColor(with: darkTraits)
        #expect(lightConnected != darkConnected)

        let lightAttention = UIColor(FichierTheme.attention).resolvedColor(with: lightTraits)
        let darkAttention = UIColor(FichierTheme.attention).resolvedColor(with: darkTraits)
        #expect(lightAttention != darkAttention)
    }
    #endif
}

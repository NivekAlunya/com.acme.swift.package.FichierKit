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
        #expect(FichierTheme.accent != FichierTheme.secondaryAccent)
        #expect(FichierTheme.accent != FichierTheme.tertiaryAccent)
        #expect(FichierTheme.secondaryAccent != FichierTheme.tertiaryAccent)
    }

    #if canImport(UIKit)
    @Test("Brand semantic colors adapt between light and dark appearances")
    func brandColorsAdaptForLightAndDarkTraits() {
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

        let lightAccent = UIColor(FichierTheme.accent).resolvedColor(with: lightTraits)
        let darkAccent = UIColor(FichierTheme.accent).resolvedColor(with: darkTraits)
        #expect(lightAccent != darkAccent)

        let lightSecondary = UIColor(FichierTheme.secondaryAccent).resolvedColor(with: lightTraits)
        let darkSecondary = UIColor(FichierTheme.secondaryAccent).resolvedColor(with: darkTraits)
        #expect(lightSecondary != darkSecondary)

        let lightTertiary = UIColor(FichierTheme.tertiaryAccent).resolvedColor(with: lightTraits)
        let darkTertiary = UIColor(FichierTheme.tertiaryAccent).resolvedColor(with: darkTraits)
        #expect(lightTertiary != darkTertiary)
    }
    #endif
}

//
//  FichierThemeTests.swift
//  FichierKitTests
//

import SwiftUI
import Testing
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import FichierKit

@Suite("FichierTheme Brand Colors")
struct FichierThemeTests {
    #if canImport(UIKit)
    @Test("Brand semantic colors resolve to distinct values and adapt for light/dark traits")
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

        #expect(lightAccent != lightSecondary)
        #expect(lightAccent != lightTertiary)
        #expect(lightSecondary != lightTertiary)
        #expect(darkAccent != darkSecondary)
        #expect(darkAccent != darkTertiary)
        #expect(darkSecondary != darkTertiary)
    }
    #elseif canImport(AppKit)
    private func resolvedSRGB(_ color: Color, with appearance: NSAppearance) -> NSColor? {
        var result: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            result = NSColor(color).usingColorSpace(.sRGB)
        }
        return result
    }

    @Test("Brand semantic colors resolve to distinct sRGB values and adapt between Aqua and Dark Aqua")
    func brandColorsAdaptForMacOSAppearances() throws {
        let light = try #require(NSAppearance(named: .aqua))
        let dark = try #require(NSAppearance(named: .darkAqua))

        let lightAccent = try #require(resolvedSRGB(FichierTheme.accent, with: light))
        let darkAccent = try #require(resolvedSRGB(FichierTheme.accent, with: dark))
        #expect(lightAccent != darkAccent)

        let lightSecondary = try #require(resolvedSRGB(FichierTheme.secondaryAccent, with: light))
        let darkSecondary = try #require(resolvedSRGB(FichierTheme.secondaryAccent, with: dark))
        #expect(lightSecondary != darkSecondary)

        let lightTertiary = try #require(resolvedSRGB(FichierTheme.tertiaryAccent, with: light))
        let darkTertiary = try #require(resolvedSRGB(FichierTheme.tertiaryAccent, with: dark))
        #expect(lightTertiary != darkTertiary)

        #expect(lightAccent != lightSecondary)
        #expect(lightAccent != lightTertiary)
        #expect(lightSecondary != lightTertiary)
        #expect(darkAccent != darkSecondary)
        #expect(darkAccent != darkTertiary)
        #expect(darkSecondary != darkTertiary)
    }
    #endif

    @Test("Atmospheric background gradient and view modifier instantiate cleanly")
    @MainActor
    func atmosphericBackgroundInstantiates() {
        _ = FichierTheme.atmosphericBackground
        _ = Text("Preview").fichierAtmosphericBackground()
    }
}

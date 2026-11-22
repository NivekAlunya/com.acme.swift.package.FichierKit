//
//  FichierTheme.swift
//  FichierKit
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Semantic brand color and surface tokens derived from the Fichier app icon (`fichier.svg` and `Back-1x.png`).
///
/// Provides adaptive light and dark variants for primary accent, connected/success,
/// and attention/warning states, as well as the atmospheric slate-indigo background gradient
/// across iOS, tvOS, and macOS targets.
public enum FichierTheme {
    // MARK: - Semantic Brand Colors

    /// Primary brand accent (Periwinkle `#A99BFF` in dark mode, `#6E5CE6` in light mode).
    public static let accent: Color = adaptiveColor(
        light: (red: 0.431, green: 0.361, blue: 0.902),
        dark: (red: 0.663, green: 0.608, blue: 1.000)
    )

    /// High-contrast dark ink foreground for use on `#A99BFF` focused pills and badges.
    public static let onAccentDark: Color = Color(red: 0.094, green: 0.078, blue: 0.180)

    /// Secondary brand accent (Seafoam Mint `#8FE3C8` in dark mode, `#2BA882` in light mode).
    public static let secondaryAccent: Color = adaptiveColor(
        light: (red: 0.169, green: 0.659, blue: 0.510),
        dark: (red: 0.561, green: 0.890, blue: 0.784)
    )

    /// Tertiary brand accent (Warm Peach `#FFBFA0` in dark mode, `#D97248` in light mode).
    public static let tertiaryAccent: Color = adaptiveColor(
        light: (red: 0.851, green: 0.447, blue: 0.282),
        dark: (red: 1.000, green: 0.749, blue: 0.627)
    )

    // MARK: - Atmospheric Surface Gradient

    /// Top-left deep slate-teal stop (`#253440`) sampled from the tvOS icon background.
    public static let surfaceTop: Color = Color(red: 0.145, green: 0.204, blue: 0.251)

    /// Mid-canvas muted dusk-slate stop (`#42526C`).
    public static let surfaceMid: Color = Color(red: 0.259, green: 0.322, blue: 0.424)

    /// Bottom-right deep midnight-indigo stop (`#272941`).
    public static let surfaceBottom: Color = Color(red: 0.153, green: 0.161, blue: 0.255)

    /// Atmospheric gradient for dark-mode and tvOS canvases.
    public static var atmosphericBackground: LinearGradient {
        LinearGradient(
            colors: [surfaceTop, surfaceMid, surfaceBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Helpers

    private static func adaptiveColor(
        light: (red: Double, green: Double, blue: Double),
        dark: (red: Double, green: Double, blue: Double)
    ) -> Color {
        #if canImport(UIKit)
        Color(
            UIColor { traits in
                let c = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1.0)
            }
        )
        #elseif canImport(AppKit)
        Color(
            NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let c = isDark ? dark : light
                return NSColor(red: c.red, green: c.green, blue: c.blue, alpha: 1.0)
            }
        )
        #else
        Color(red: dark.red, green: dark.green, blue: dark.blue)
        #endif
    }
}

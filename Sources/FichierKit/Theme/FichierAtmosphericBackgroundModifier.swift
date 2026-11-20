//
//  FichierAtmosphericBackgroundModifier.swift
//  FichierKit
//

import SwiftUI

/// Applies the Fichier atmospheric slate-indigo gradient on tvOS and in dark mode on iOS/macOS,
/// while preserving the native system background in light mode.
public struct FichierAtmosphericBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public func body(content: Content) -> some View {
        content.background {
            #if os(tvOS)
            FichierTheme.atmosphericBackground
                .ignoresSafeArea()
            #else
            if colorScheme == .dark {
                FichierTheme.atmosphericBackground
                    .ignoresSafeArea()
            }
            #endif
        }
    }
}

public extension View {
    /// Applies the Fichier atmospheric slate-indigo gradient on tvOS and dark-mode iOS/macOS canvases.
    func fichierAtmosphericBackground() -> some View {
        modifier(FichierAtmosphericBackgroundModifier())
    }
}

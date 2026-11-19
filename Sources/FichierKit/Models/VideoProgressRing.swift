//
//  VideoProgressRing.swift
//  FichierKit
//
//

import SwiftUI

/// Compact circular progress indicator rendered on video thumbnail badges to indicate watch progress.
///
/// Draws a subtle translucent track ring beneath a trimmed progress arc with rounded line caps.
/// Automatically clamps input progress between `0.0` and `1.0`.
public struct VideoProgressRing: View {
    /// Normalized playback progress value between `0.0` (unplayed) and `1.0` (completed).
    public let progress: Double

    /// Bounding width and height of the circular indicator in points.
    public var size: CGFloat

    /// Stroke line width in points.
    public var lineWidth: CGFloat

    /// Color of the foreground progress stroke arc.
    public var ringColor: Color

    /// Designated public initializer.
    ///
    /// - Parameters:
    ///   - progress: Normalized playback percentage (clamped to 0.0...1.0).
    ///   - size: Diameter of the ring (defaults to 14.0 points).
    ///   - lineWidth: Stroke width (defaults to 2.0 points).
    ///   - ringColor: Progress stroke tint (defaults to `.white`).
    public init(
        progress: Double,
        size: CGFloat = 14.0,
        lineWidth: CGFloat = 2.0,
        ringColor: Color = .white
    ) {
        self.progress = max(0.0, min(1.0, progress))
        self.size = size
        self.lineWidth = lineWidth
        self.ringColor = ringColor
    }

    public var body: some View {
        ZStack {
            // Subtle background track
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: lineWidth)

            // Progress arc
            Circle()
                .trim(from: 0.0, to: CGFloat(max(0.05, progress)))
                .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

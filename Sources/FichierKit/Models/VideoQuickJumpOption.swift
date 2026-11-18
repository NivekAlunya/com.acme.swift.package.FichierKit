//
//  VideoQuickJumpOption.swift
//  FichierKit
//
//

import Foundation

/// Quick-jump percentage or fixed-offset target offered in the HUD Chapters & Jump menu.
public struct VideoQuickJumpOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let targetTime: Double

    public init(id: String, label: String, targetTime: Double) {
        self.id = id
        self.label = label
        self.targetTime = targetTime
    }

    /// Generates contextual quick-jump presets (`0%`, `25%`, `50%`, `75%`, `-10m`, `+10m`, `+30m`) for a video duration.
    public static func buildOptions(duration: Double, currentTime: Double) -> [VideoQuickJumpOption] {
        guard duration.isFinite, !duration.isNaN, duration > 0 else {
            return []
        }

        let safeCurrent = (currentTime.isFinite && !currentTime.isNaN) ? max(0, min(duration, currentTime)) : 0
        var options: [VideoQuickJumpOption] = [
            VideoQuickJumpOption(id: "pct_0", label: "Start (0%)", targetTime: 0),
            VideoQuickJumpOption(id: "pct_25", label: "25%", targetTime: duration * 0.25),
            VideoQuickJumpOption(id: "pct_50", label: "50%", targetTime: duration * 0.50),
            VideoQuickJumpOption(id: "pct_75", label: "75%", targetTime: duration * 0.75)
        ]

        if safeCurrent > 60 {
            options.append(
                VideoQuickJumpOption(
                    id: "rel_back_10m",
                    label: "-10 min",
                    targetTime: max(0, safeCurrent - 600)
                )
            )
        }

        if safeCurrent + 600 < duration {
            options.append(
                VideoQuickJumpOption(
                    id: "rel_fwd_10m",
                    label: "+10 min",
                    targetTime: min(duration, safeCurrent + 600)
                )
            )
        }

        if duration >= 3600, safeCurrent + 1800 < duration {
            options.append(
                VideoQuickJumpOption(
                    id: "rel_fwd_30m",
                    label: "+30 min",
                    targetTime: min(duration, safeCurrent + 1800)
                )
            )
        }

        return options
    }

    /// Formats a timestamp in seconds into `MM:SS` or `HH:MM:SS` matching chapter display.
    public static func formattedTimestamp(_ seconds: Double) -> String {
        MediaFormatHelper.formatTimestamp(seconds, zeroPaddedHours: true)
    }
}

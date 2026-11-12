//
//  CrashReporting.swift
//  FichierKit
//

import Foundation
#if DEBUG
import Wappn
#endif

/// Bridges the Wappn crash catcher to the app's durable `CrashReportStore`.
///
/// Call `start()` once, as early as possible at launch. It archives any crash from the previous run and
/// then arms Wappn's uncaught-exception and fatal-signal handlers for the current run.
///
/// ### How a crash becomes a report
/// - **Objective-C exception**: Wappn writes `last_crash.json` (reason + call stack) while crashing.
/// - **Fatal signal** (e.g. `SIGSEGV`, `SIGTRAP`): the handler may only call async-signal-safe
///   functions, so it writes a tiny tombstone with the signal name. Wappn converts it into
///   `last_crash.json` on the *next* launch (inside `Wappn.shared` initialization).
///
/// Either way the report is only visible at the next launch, which is why `start()` archives it then.
///
/// ### Debug builds only
/// Wappn and Crashlytics (planned for release) both install process-wide exception and signal handlers
/// and neither chains to the other, so running both would silently lose crashes in one of them.
/// Wappn is therefore active only in `DEBUG`; `start()` is a no-op in release builds, leaving the
/// crash handlers free for Crashlytics.
public nonisolated enum CrashReporting {

    /// Archives a pending crash from the previous session (if any) and starts crash monitoring.
    ///
    /// - Parameter store: Destination for archived reports.
    public static func start(store: CrashReportStore = CrashReportStore()) {
        #if DEBUG
        // Touching `Wappn.shared` runs its tombstone recovery, which must happen before the check below.
        let wappn = Wappn.shared

        if wappn.didCrashLastTime(), let crash = wappn.getLastCrashInfo() {
            let text = reportText(for: crash, recoveredAt: Date())
            do {
                let url = try store.archive(text)
                logi("Archived crash report \(url.lastPathComponent)")
                // Only drop Wappn's marker once the report is safely on disk, so a failed write is retried next launch.
                wappn.clearCrashMarker()
            } catch {
                loge("Failed to archive crash report: \(error.localizedDescription)")
            }
        }

        // Intentionally NOT calling `markLaunchSuccess()`: it deletes the crash marker, which would race
        // with archiving above if the order ever changes, and the store already owns report lifetime.
        wappn.startIntercepting(interceptCrashes: true)
        #endif
    }

    #if DEBUG

    /// Regular expression detecting credentials embedded in URI schemes (e.g. `smb://user:password@host` or `http://user:password@host`).
    private static let credentialURIRegex: NSRegularExpression = {
        let pattern = #"([a-zA-Z][a-zA-Z0-9+.-]*://[^:\s/@]+):([^@\s/]+)@"#
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            assertionFailure("Invalid credential redaction regex: \(error)")
            // Fall back to a regex that matches nothing rather than the empty string
            return (try? NSRegularExpression(pattern: "$^")) ?? NSRegularExpression()
        }
    }()

    /// Sanitizes plain-text strings by masking embedded user passwords in URIs.
    public static func redactCredentials(in text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return credentialURIRegex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: "$1:***@"
        )
    }

    /// Builds the shareable text for a crash, with all embedded credentials redacted.
    ///
    /// - Parameters:
    ///   - crash: Crash details decoded by Wappn.
    ///   - recoveredAt: When the report was recovered (the launch after the crash).
    public static func reportText(for crash: CrashInfo, recoveredAt: Date) -> String {
        let bundle = Bundle.main.infoDictionary
        let build = bundle?["CFBundleVersion"] as? String ?? "?"
        // Signal crashes are recovered from a tombstone that stores no real time (Wappn writes 0),
        // so a 1970 timestamp means "unknown" and the recovery time is the best available bound.
        let crashTimeKnown = crash.timestamp.timeIntervalSince1970 > 86_400
        let crashTime = crashTimeKnown ? crash.timestamp.formatted(.iso8601) : "unknown (before next launch)"

        let rawReport = """
        Fichier crash report
        Build: \(build)
        Crash time: \(crashTime)
        Recovered at: \(recoveredAt.formatted(.iso8601))

        \(crash.description)
        """
        return redactCredentials(in: rawReport)
    }
    #endif
}

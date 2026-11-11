//
//  VLCPlaybackOptions.swift
//  FichierKit
//
//

import Foundation

/// Configuration options and `smb://` URL helpers for `VLCMedia` playback in `TVVLCPlayerEngine`.
public struct VLCPlaybackOptions: Sendable, Equatable {
    /// Default LibVLC `network-caching` buffer window in milliseconds, matching `kVLCSettingNetworkCachingDefaultValue`.
    public static let defaultNetworkCachingMs: Int = 999

    /// Default NetBIOS / SMB workgroup domain passed to LibVLC when no explicit domain is provided.
    public static let defaultSMBDomain: String = "WORKGROUP"

    /// Default LibVLC `avcodec-skiploopfilter` level (`"1"` skips deblocking loop filter on non-reference frames,
    /// matching `kVLCSettingSkipLoopFilterNonRef` in VLC for iOS/tvOS).
    public static let defaultSkipLoopFilter: String = "1"

    /// Default subtitle text encoding matching VLC for iOS (`kVLCSettingTextEncodingDefaultValue`).
    public static let defaultSubsdecEncoding: String = "Windows-1252"

    /// LibVLC Matroska demuxer option that trusts `CueClusterPosition` (`SEEK_TRUST_CUETIME`) without verifying
    /// a backward pre-roll cluster over SMB (`modules/demux/mkv/mkv.cpp`).
    public static let mkvTrustedDemux: String = "mkv_trusted"

    private static let matroskaExtensions: Set<String> = ["mkv", "mka", "mks", "webm"]

    public let username: String?
    public let password: String?
    public let domain: String?
    public let networkCachingMs: Int
    public let skipLoopFilter: String
    public let subsdecEncoding: String

    /// Initializes LibVLC per-media playback options.
    ///
    /// - Parameters:
    ///   - username: Optional SMB account username (`nil` for non-SMB sources).
    ///   - password: Optional SMB account password.
    ///   - domain: Optional SMB workgroup or Active Directory domain (defaults to `"WORKGROUP"` when SMB options are emitted).
    ///   - networkCachingMs: Read-ahead network caching buffer in milliseconds (default `999`).
    ///   - skipLoopFilter: LibVLC `avcodec-skiploopfilter` level string (default `"1"` for non-reference frames).
    ///   - subsdecEncoding: LibVLC `subsdec-encoding` string (default `"Windows-1252"`).
    public init(
        username: String? = nil,
        password: String? = nil,
        domain: String? = nil,
        networkCachingMs: Int = VLCPlaybackOptions.defaultNetworkCachingMs,
        skipLoopFilter: String = VLCPlaybackOptions.defaultSkipLoopFilter,
        subsdecEncoding: String = VLCPlaybackOptions.defaultSubsdecEncoding
    ) {
        self.username = username
        self.password = password
        self.domain = domain
        self.networkCachingMs = max(0, networkCachingMs)
        let trimmedLoopFilter = skipLoopFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        self.skipLoopFilter = trimmedLoopFilter.isEmpty ? Self.defaultSkipLoopFilter : trimmedLoopFilter
        let trimmedEncoding = subsdecEncoding.trimmingCharacters(in: .whitespacesAndNewlines)
        self.subsdecEncoding = trimmedEncoding.isEmpty ? Self.defaultSubsdecEncoding : trimmedEncoding
    }

    /// Constructs the options dictionary passed to `VLCMedia.addOptions(_:)`.
    ///
    /// Always configures `"network-caching"`, `"avcodec-skiploopfilter"`, and `"subsdec-encoding"`.
    /// Enables `"demux": "mkv_trusted"` for Matroska containers (`mkv`, `mka`, `mks`, `webm`) so LibVLC
    /// trusts `CueClusterPosition` directly during seeks over SMB. Includes `"smb-user"`, `"smb-pwd"`,
    /// and `"smb-domain"` whenever SMB credentials are present or the target URL uses the `smb://` scheme.
    ///
    /// - Parameter url: Optional media URL used to detect Matroska containers and `smb://` scheme.
    /// - Returns: Option dictionary suitable for `VLCMedia.addOptions(_:)`.
    public func makeVLCMediaOptionsDictionary(for url: URL? = nil) -> [String: Any] {
        var options: [String: Any] = [
            "network-caching": networkCachingMs,
            "avcodec-skiploopfilter": skipLoopFilter,
            "subsdec-encoding": subsdecEncoding
        ]

        if let ext = url?.pathExtension.lowercased(), Self.matroskaExtensions.contains(ext) {
            options["demux"] = Self.mkvTrustedDemux
        }

        let isSMBScheme = url?.scheme?.lowercased() == "smb"
        let hasCredentials = username != nil || password != nil || domain != nil
        if isSMBScheme || hasCredentials {
            let trimmedDomain = domain?.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveDomain: String
            if let trimmedDomain, !trimmedDomain.isEmpty {
                effectiveDomain = trimmedDomain
            } else {
                effectiveDomain = Self.defaultSMBDomain
            }

            options["smb-user"] = username ?? ""
            options["smb-pwd"] = password ?? ""
            options["smb-domain"] = effectiveDomain
        }

        return options
    }

    /// Builds a direct `smb://` URL from SMB server host metadata, share name, and share-relative path.
    ///
    /// Sanitizes accidental `smb://` prefixes and IPv6 scope suffixes (`%en0`), wraps raw IPv6 literals
    /// in brackets for `URLComponents`, and percent-encodes each share and path component safely.
    ///
    /// - Parameters:
    ///   - host: Server IP address, hostname, or mDNS name.
    ///   - port: Optional TCP port (`1...65535`). Pass `nil` to omit the explicit port.
    ///   - share: Exported SMB share name.
    ///   - relativePath: Path of the file within the share.
    /// - Returns: A properly encoded `smb://` `URL`, or `nil` if host, port, or share is invalid.
    public static func makeSMBURL(
        host: String,
        port: Int? = nil,
        share: String,
        relativePath: String = ""
    ) -> URL? {
        guard let normalizedHost = sanitizeHost(host) else {
            return nil
        }

        if let port, !(1...65535).contains(port) {
            return nil
        }

        let normalizedShare = share.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalizedShare.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let shareSegments = normalizedShare
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let pathSegments = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0 != "." }

        let allSegments = shareSegments + pathSegments
        guard !allSegments.isEmpty else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "smb"
        components.host = normalizedHost
        components.port = port
        components.path = "/" + allSegments.joined(separator: "/")
        return components.url
    }

    private static func sanitizeHost(_ rawHost: String) -> String? {
        var candidate = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.lowercased().hasPrefix("smb://") {
            candidate = String(candidate.dropFirst(6))
        }
        candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let hadBrackets = candidate.hasPrefix("[") && candidate.hasSuffix("]")
        var core = hadBrackets ? String(candidate.dropFirst().dropLast()) : candidate
        if let scopeSeparator = core.firstIndex(of: "%") {
            core = String(core[..<scopeSeparator])
        }
        core = core.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !core.isEmpty else {
            return nil
        }

        let colonCount = core.count { $0 == ":" }
        if hadBrackets || colonCount >= 2 {
            return "[\(core)]"
        }
        if colonCount == 1 {
            return nil
        }
        return core
    }
}

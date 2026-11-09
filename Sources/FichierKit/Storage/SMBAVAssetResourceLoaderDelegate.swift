//
//  SMBAVAssetResourceLoaderDelegate.swift
//  FichierKit
//
//

import Foundation
import AVFoundation
import UniformTypeIdentifiers

/// `AVAssetResourceLoaderDelegate` streaming native video byte ranges on demand from an `SMBClientProtocol`
/// over the custom `smbstream://` URL scheme without local HTTP loopback sockets or disk buffering.
public nonisolated final class SMBAVAssetResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, Sendable {
    public static let scheme = "smbstream"

    private let client: any SMBClientProtocol
    private let share: String
    private let path: String
    private let fileName: String
    private let fileSize: Int64
    private let chunkSize: Int
    private let taskTracker = SMBResourceLoadingTaskTracker()

    public init(
        client: any SMBClientProtocol,
        share: String,
        path: String,
        fileName: String,
        fileSize: Int64,
        chunkSize: Int = 256 * 1024
    ) {
        self.client = client
        self.share = share
        self.path = path
        self.fileName = fileName
        self.fileSize = fileSize
        self.chunkSize = chunkSize
        super.init()
    }

    public static func makeStreamURL(fileName: String) -> URL {
        let ext = (fileName as NSString).pathExtension
        let safeExt = ext.isEmpty ? "mp4" : ext
        return URL(string: "\(scheme)://stream/\(UUID().uuidString).\(safeExt)") ?? URL(fileURLWithPath: "/")
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard fileSize > 0 else {
            loadingRequest.finishLoading(with: NSError(
                domain: "SMBAVAssetResourceLoaderDelegate",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unknown SMB video file size."]
            ))
            return true
        }

        if let info = loadingRequest.contentInformationRequest {
            let ext = (fileName as NSString).pathExtension.lowercased()
            if let utType = UTType(filenameExtension: ext) {
                info.contentType = utType.identifier
            } else if ext == "mov" {
                info.contentType = "com.apple.quicktime-movie"
            } else {
                info.contentType = "public.mpeg-4"
            }
            info.contentLength = fileSize
            info.isByteRangeAccessSupported = true
        }

        guard let dataRequest = loadingRequest.dataRequest else {
            loadingRequest.finishLoading()
            return true
        }

        let startOffset = dataRequest.currentOffset
        let remaining = max(0, fileSize - startOffset)
        let requestedCount = dataRequest.requestsAllDataToEndOfResource
            ? remaining
            : Int64(dataRequest.requestedLength)
        let safeLength = Int(min(max(0, requestedCount), remaining, Int64(Int.max)))

        guard safeLength > 0 else {
            loadingRequest.finishLoading()
            return true
        }

        let targetEnd = startOffset + Int64(safeLength)
        let tracker = self.taskTracker
        let targetClient = self.client
        let targetShare = self.share
        let targetPath = self.path
        let targetChunkSize = self.chunkSize
        let requestID = ObjectIdentifier(loadingRequest)

        Task {
            await tracker.runTask(for: requestID, isCancelled: loadingRequest.isCancelled) {
                do {
                    var currentOffset = startOffset
                    var reachedPrematureEOF = false

                    while currentOffset < targetEnd {
                        if Task.isCancelled || loadingRequest.isCancelled {
                            if !loadingRequest.isCancelled && !loadingRequest.isFinished {
                                loadingRequest.finishLoading(with: CancellationError())
                            }
                            return
                        }

                        let bytesToRead = min(targetChunkSize, Int(targetEnd - currentOffset))
                        let chunk = try await targetClient.readMediaRange(
                            share: targetShare,
                            path: targetPath,
                            offset: currentOffset,
                            length: bytesToRead
                        )

                        if Task.isCancelled || loadingRequest.isCancelled {
                            if !loadingRequest.isCancelled && !loadingRequest.isFinished {
                                loadingRequest.finishLoading(with: CancellationError())
                            }
                            return
                        }
                        if chunk.isEmpty {
                            reachedPrematureEOF = true
                            break
                        }

                        dataRequest.respond(with: chunk)
                        currentOffset += Int64(chunk.count)
                    }

                    if !loadingRequest.isCancelled && !loadingRequest.isFinished {
                        if Task.isCancelled {
                            loadingRequest.finishLoading(with: CancellationError())
                        } else if currentOffset >= targetEnd {
                            loadingRequest.finishLoading()
                        } else if reachedPrematureEOF {
                            loadingRequest.finishLoading(with: NSError(
                                domain: "SMBAVAssetResourceLoaderDelegate",
                                code: -2,
                                userInfo: [NSLocalizedDescriptionKey: "Unexpected EOF at offset \(currentOffset) of \(targetEnd)."]
                            ))
                        } else {
                            loadingRequest.finishLoading(with: NSError(
                                domain: "SMBAVAssetResourceLoaderDelegate",
                                code: -3,
                                userInfo: [NSLocalizedDescriptionKey: "Incomplete byte range read."]
                            ))
                        }
                    }
                } catch {
                    if !loadingRequest.isCancelled && !loadingRequest.isFinished {
                        loadingRequest.finishLoading(with: error)
                    }
                }
            }
        }

        return true
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        let requestID = ObjectIdentifier(loadingRequest)
        Task { [taskTracker] in
            await taskTracker.cancelTask(for: requestID)
        }
    }

    public nonisolated func cancelAll() {
        Task { [taskTracker] in
            await taskTracker.cancelAll()
        }
    }
}

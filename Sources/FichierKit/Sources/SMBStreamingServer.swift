//
//  SMBStreamingServer.swift
//  FichierKit
//
//

import Foundation
import Network

/// Loopback HTTP 1.1 byte-range server bridging SMB reads for both `AVPlayer` and `TVVLCPlayerEngine` without disk caching.
public actor SMBStreamingServer {
    private let client: any SMBClientProtocol
    private let share: String
    private let path: String
    private let fileName: String
    private var totalSize: Int64

    private var listener: NWListener?
    private var activeConnections: [NWConnection] = []
    private var serverPort: UInt16?
    private var startupContinuations: [CheckedContinuation<URL, any Error>] = []

    /// Upper bound for a single `206` response body. Players asking for open-ended ranges
    /// (`bytes=N-`) receive at most this much and issue a follow-up range request, which keeps
    /// memory bounded instead of buffering the remainder of a multi-GB file.
    private static let maxChunkSize: Int = 2 * 1024 * 1024
    /// Read size used when streaming an un-ranged `200 OK` body chunk by chunk over SMB.
    private static let streamChunkSize: Int = 512 * 1024

    public init(
        client: any SMBClientProtocol,
        share: String,
        path: String,
        fileName: String,
        totalSize: Int64
    ) {
        self.client = client
        self.share = share
        self.path = path
        self.fileName = fileName
        self.totalSize = totalSize
    }

    /// Starts the loopback listener on `127.0.0.1` and returns the streamable URL.
    public func start() async throws -> URL {
        if let port = serverPort {
            return makeStreamURL(for: port)
        }

        if totalSize <= 0 {
            totalSize = (try? await client.fileSize(share: share, path: path)) ?? 0
        }

        // Loopback-only: the server must never be reachable from the network because it serves
        // unauthenticated access to an SMB file using the user's stored credentials.
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback

        let newListener = try NWListener(using: parameters, on: .any)
        self.listener = newListener

        // The listener reports readiness asynchronously on a Network.framework queue. Callers are
        // parked in `startupContinuations` and resumed from `handleListenerStateUpdate`, or with
        // `CancellationError` from `stop()`, so every continuation is resumed exactly once.
        return try await withCheckedThrowingContinuation { continuation in
            self.startupContinuations.append(continuation)

            newListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                Task {
                    await self.handleListenerStateUpdate(state)
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                Task {
                    await self.handleNewConnection(connection)
                }
            }

            // Network.framework's callback API requires a GCD queue; handlers hop back onto this actor.
            newListener.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Stops the HTTP listener and closes all in-flight socket connections.
    public func stop() {
        let continuations = startupContinuations
        startupContinuations.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: CancellationError())
        }

        listener?.cancel()
        listener = nil
        serverPort = nil

        for connection in activeConnections {
            connection.cancel()
        }
        activeConnections.removeAll()
    }

    // MARK: - Connection Management

    private func handleListenerStateUpdate(_ state: NWListener.State) {
        let continuations = startupContinuations
        guard !continuations.isEmpty else { return }

        switch state {
        case .ready:
            if let port = listener?.port?.rawValue {
                self.serverPort = port
                self.startupContinuations.removeAll()
                let url = makeStreamURL(for: port)
                for continuation in continuations {
                    continuation.resume(returning: url)
                }
            }
        case .failed(let error):
            self.listener = nil
            self.startupContinuations.removeAll()
            for continuation in continuations {
                continuation.resume(throwing: error)
            }
        case .cancelled:
            self.listener = nil
            self.startupContinuations.removeAll()
            for continuation in continuations {
                continuation.resume(throwing: CancellationError())
            }
        default:
            break
        }
    }

    private func makeStreamURL(for port: UInt16) -> URL {
        let safeName = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "stream.bin"
        return URL(string: "http://127.0.0.1:\(port)/\(safeName)") ?? URL(fileURLWithPath: "/")
    }

    private func handleNewConnection(_ connection: NWConnection) {
        activeConnections.append(connection)

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .cancelled, .failed:
                Task {
                    await self.removeConnection(connection)
                }
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
        receiveNextChunk(on: connection)
    }

    private func removeConnection(_ connection: NWConnection) {
        activeConnections.removeAll { $0 === connection }
    }

    private nonisolated func receiveNextChunk(on connection: NWConnection, buffer: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] content, _, isComplete, error in
            guard let self, let connection else { return }
            if error != nil {
                connection.cancel()
                return
            }

            var accumulated = buffer
            if let content, !content.isEmpty {
                accumulated.append(content)
            }

            // A request is complete once the header terminator (CRLF CRLF) arrives. Bare LF LF is
            // accepted too because some clients are lenient. Requests are accumulated across reads
            // since TCP may split the headers over several segments; 64 KB caps abusive input.
            let headerEnd = Data([0x0D, 0x0A, 0x0D, 0x0A])
            let fallbackEnd = Data([0x0A, 0x0A])
            let hasCompletedHeaders = accumulated.range(of: headerEnd) != nil || accumulated.range(of: fallbackEnd) != nil

            if hasCompletedHeaders {
                Task {
                    await self.processHTTPRequest(accumulated, on: connection)
                }
            } else if isComplete {
                if !accumulated.isEmpty {
                    Task {
                        await self.processHTTPRequest(accumulated, on: connection)
                    }
                } else {
                    connection.cancel()
                }
            } else if accumulated.count > 65536 {
                self.sendHTTPResponse(status: "400 Bad Request", headers: [:], body: nil, on: connection)
            } else {
                self.receiveNextChunk(on: connection, buffer: accumulated)
            }
        }
    }

    private func processHTTPRequest(_ data: Data, on connection: NWConnection) async {
        guard let requestString = String(data: data, encoding: .utf8),
              let firstLine = requestString.components(separatedBy: "\r\n").first,
              firstLine.components(separatedBy: " ").count >= 2 else {
            sendHTTPResponse(status: "400 Bad Request", headers: [:], body: nil, on: connection)
            return
        }

        let lines = requestString.components(separatedBy: "\r\n")
        let method = firstLine.components(separatedBy: " ")[0].uppercased()
        let contentType = SupportedMediaTypes.mimeType(for: (fileName as NSString).pathExtension)

        if totalSize <= 0 {
            totalSize = (try? await client.fileSize(share: share, path: path)) ?? 0
        }

        if method == "HEAD" {
            let headers: [String: String] = [
                "Accept-Ranges": "bytes",
                "Content-Length": "\(totalSize)",
                "Content-Type": contentType,
                "Connection": "close"
            ]
            sendHTTPResponse(status: "200 OK", headers: headers, body: nil, on: connection)
            return
        }

        var rangeHeader: String?
        for line in lines where line.lowercased().hasPrefix("range:") {
            rangeHeader = line
            break
        }

        if let rangeHeader {
            guard let (start, end) = HTTPRangeParser.parse(rangeHeader, totalSize: totalSize) else {
                let headers: [String: String] = [
                    "Content-Range": "bytes */\(totalSize)",
                    "Connection": "close"
                ]
                sendHTTPResponse(status: "416 Range Not Satisfiable", headers: headers, body: nil, on: connection)
                return
            }

            let requestedLength = Int(min(end - start + 1, Int64(Int.max)))
            // Serve a shorter-than-requested range if needed; `Content-Range` below reports the
            // bytes actually returned, which HTTP clients (AVPlayer, VLC) handle by re-requesting.
            let fetchLength = min(requestedLength, Self.maxChunkSize)

            do {
                let payload = try await client.readMediaRange(share: share, path: path, offset: start, length: fetchLength)
                guard !Task.isCancelled else {
                    connection.cancel()
                    return
                }
                guard !payload.isEmpty else {
                    sendHTTPResponse(status: "500 Internal Server Error", headers: [:], body: nil, on: connection)
                    return
                }
                // The SMB read may return fewer bytes than asked (EOF, short read), so derive the end from the payload.
                let actualEnd = start + Int64(payload.count) - 1
                let headers: [String: String] = [
                    "Content-Type": contentType,
                    "Content-Range": "bytes \(start)-\(actualEnd)/\(totalSize)",
                    "Content-Length": "\(payload.count)",
                    "Accept-Ranges": "bytes",
                    "Connection": "close"
                ]
                sendHTTPResponse(status: "206 Partial Content", headers: headers, body: payload, on: connection)
            } catch is CancellationError {
                connection.cancel()
            } catch {
                sendHTTPResponse(status: "500 Internal Server Error", headers: [:], body: nil, on: connection)
            }
        } else {
            guard totalSize > 0 else {
                sendHTTPResponse(status: "404 Not Found", headers: [:], body: nil, on: connection)
                return
            }

            let headers: [String: String] = [
                "Content-Type": contentType,
                "Content-Length": "\(totalSize)",
                "Accept-Ranges": "bytes",
                "Connection": "close"
            ]
            guard await sendHTTPHeader(status: "200 OK", headers: headers, on: connection) else {
                connection.cancel()
                return
            }

            await streamFullBody(from: 0, totalSize: totalSize, on: connection)
        }
    }

    private func streamFullBody(from startOffset: Int64, totalSize: Int64, on connection: NWConnection) async {
        var currentOffset = startOffset

        // Each iteration reads one chunk and awaits the socket flush before the next read, giving
        // natural back-pressure so a slow player never makes us buffer the whole file in memory.
        // Aborts as soon as the player closes the connection (e.g. seeks elsewhere).
        while currentOffset < totalSize {
            if Task.isCancelled || !isConnectionActive(connection) {
                connection.cancel()
                return
            }

            let remaining = totalSize - currentOffset
            let bytesToRead = Int(min(remaining, Int64(Self.streamChunkSize)))

            do {
                let chunk = try await client.readMediaRange(
                    share: share,
                    path: path,
                    offset: currentOffset,
                    length: bytesToRead
                )

                if Task.isCancelled || !isConnectionActive(connection) || chunk.isEmpty {
                    connection.cancel()
                    return
                }

                let sent = await sendDataChunk(chunk, on: connection)
                guard sent else {
                    connection.cancel()
                    return
                }

                currentOffset += Int64(chunk.count)
            } catch {
                connection.cancel()
                return
            }
        }

        connection.cancel()
    }

    private func isConnectionActive(_ connection: NWConnection) -> Bool {
        activeConnections.contains { $0 === connection }
    }

    private nonisolated func buildHeaderData(status: String, headers: [String: String]) -> Data {
        var response = "HTTP/1.1 \(status)\r\n"
        for (key, value) in headers {
            response += "\(key): \(value)\r\n"
        }
        response += "\r\n"
        return Data(response.utf8)
    }

    private nonisolated func sendHTTPHeader(
        status: String,
        headers: [String: String],
        on connection: NWConnection
    ) async -> Bool {
        let headerData = buildHeaderData(status: status, headers: headers)
        return await sendDataChunk(headerData, on: connection)
    }

    private nonisolated func sendDataChunk(_ data: Data, on connection: NWConnection) async -> Bool {
        await withCheckedContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                continuation.resume(returning: error == nil)
            })
        }
    }

    private nonisolated func sendHTTPResponse(
        status: String,
        headers: [String: String],
        body: Data?,
        on connection: NWConnection
    ) {
        var fullData = buildHeaderData(status: status, headers: headers)
        if let body {
            fullData.append(body)
        }

        connection.send(content: fullData, completion: .contentProcessed { [weak connection] _ in
            connection?.cancel()
        })
    }
}

import Foundation

/// Minimal Server-Sent Events parser sufficient for OpenAI- and
/// Anthropic-style streaming endpoints.
///
/// Both providers emit one event per line of the form:
///   `data: {…json…}`
/// terminated by a blank line. The terminal sentinel is either an explicit
/// `[DONE]` line (OpenAI) or an event field like `event: message_stop`
/// (Anthropic). Consumers parse the JSON payload themselves; this type is
/// only responsible for splitting the byte stream into individual data
/// payload strings.
struct SSEParser {
    /// Parse an `AsyncThrowingStream<Data, Error>` of HTTP-body byte chunks
    /// into an `AsyncThrowingStream<String, Error>` of `data:` payloads.
    static func payloadStream(
        from byteStream: AsyncThrowingStream<Data, Error>
    ) -> AsyncThrowingStream<String, Error> {
        // Guard against a misbehaving server that streams indefinitely
        // without ever emitting a newline — without this the line buffer
        // would grow until the app runs out of memory. A single SSE data
        // line is realistically well under this ceiling.
        let maxBufferedBytes = 16 * 1024 * 1024

        return AsyncThrowingStream { continuation in
            Task {
                var buffer = Data()
                do {
                    for try await chunk in byteStream {
                        buffer.append(chunk)

                        if buffer.count > maxBufferedBytes {
                            AppLog.ai.error("SSE buffer exceeded \(maxBufferedBytes) bytes without a line break; aborting stream.")
                            continuation.finish(throwing: AIProviderError.invalidResponse)
                            return
                        }
                        // Process complete lines (separated by \n).
                        while let newlineRange = buffer.range(of: Data([0x0A])) {
                            let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
                            buffer.removeSubrange(0..<newlineRange.upperBound)

                            guard let line = String(data: lineData, encoding: .utf8) else { continue }
                            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.isEmpty { continue }
                            // Recognize "data:" payload lines.
                            if trimmed.hasPrefix("data:") {
                                let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                                if payload == "[DONE]" {
                                    continuation.finish()
                                    return
                                }
                                continuation.yield(payload)
                            }
                            // event: / id: / retry: lines — ignored for our purposes.
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

/// Convert URLSession's `bytes(for:)` byte stream into an
/// `AsyncThrowingStream<Data, Error>` of variable-size chunks. We accumulate
/// up to ~4 KiB between emissions to keep parsing efficient without
/// introducing meaningful delay.
extension AsyncThrowingStream where Element == Data, Failure == Error {
    /// Collect a (typically error) response body into a single `Data`, capped
    /// so a misbehaving server returning a huge non-2xx body can't exhaust
    /// memory while we read its message. 64 KB is far larger than any real
    /// API error payload. Returns whatever was read if the stream throws.
    func collectBody(maxBytes: Int = 64 * 1024) async -> Data {
        var collected = Data()
        do {
            for try await chunk in self {
                collected.append(chunk)
                if collected.count >= maxBytes { break }
            }
        } catch {
            // Return whatever we managed to read; the caller only needs an
            // approximate error message.
        }
        return collected
    }
}

extension URLSession {
    func dataChunks(for request: URLRequest) async throws -> (AsyncThrowingStream<Data, Error>, URLResponse) {
        let (bytes, response) = try await self.bytes(for: request)
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            Task {
                var buffer = Data()
                buffer.reserveCapacity(4096)
                do {
                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= 4096 {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        return (stream, response)
    }
}

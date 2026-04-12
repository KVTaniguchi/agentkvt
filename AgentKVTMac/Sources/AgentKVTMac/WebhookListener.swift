import Foundation
import Network

/// Listens on a local TCP port for HTTP POST requests. On each request, fires `onPayload`
/// with the raw request body and responds with 200 OK. Uses Network.framework
/// (zero external dependencies). Intended for LAN-local triggers only.
///
/// Buffers across multiple `receive` callbacks until headers + full `Content-Length` body
/// are present. A single-shot read is insufficient: Ruby's `Net::HTTP` and other clients
/// can split headers and body across TCP segments; previously we ACKed 200 without ever
/// calling `onPayload`, leaving Rails tasks stuck `in_progress`.
final class WebhookListener: @unchecked Sendable {
    private let port: NWEndpoint.Port
    let onPayload: @Sendable (String) -> Void
    private var listener: NWListener?

    private static let headerSeparator = Data("\r\n\r\n".utf8)
    private static let maxRequestBytes = 512 * 1024

    init(port: UInt16 = 8765, onPayload: @escaping @Sendable (String) -> Void) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.onPayload = onPayload
    }

    func start() {
        attemptBind(attempt: 1)
    }

    private func attemptBind(attempt: Int) {
        guard let listener = try? NWListener(using: .tcp, on: port) else {
            print("WebhookListener: failed to create listener on port \(port)")
            return
        }
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                print("WebhookListener: listening on port \(self.port)")
            case .failed(let err):
                self.listener = nil
                if attempt < 5 {
                    print("WebhookListener: bind failed (\(err)), retrying in 3s (attempt \(attempt)/5)…")
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
                        self.attemptBind(attempt: attempt + 1)
                    }
                } else {
                    print("WebhookListener: could not bind port \(self.port) after 5 attempts: \(err)")
                }
            default:
                break
            }
        }
        listener.start(queue: .global(qos: .utility))
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .utility))
        readRequest(conn: conn, buffer: Data())
    }

    private func readRequest(conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else {
                conn.cancel()
                return
            }
            if error != nil {
                conn.cancel()
                return
            }
            var buf = buffer
            if let data, !data.isEmpty {
                buf.append(data)
            }
            if buf.count > Self.maxRequestBytes {
                conn.cancel()
                return
            }

            guard let sepRange = buf.range(of: Self.headerSeparator) else {
                if isComplete {
                    conn.cancel()
                } else {
                    self.readRequest(conn: conn, buffer: buf)
                }
                return
            }

            let headerData = buf[..<sepRange.lowerBound]
            guard let headerText = String(data: Data(headerData), encoding: .utf8) else {
                conn.cancel()
                return
            }

            let bodyStart = sepRange.upperBound
            let contentLength = Self.parseContentLength(headerLines: headerText)

            if let expected = contentLength {
                let have = buf.count - bodyStart
                if have < expected {
                    if isComplete {
                        conn.cancel()
                    } else {
                        self.readRequest(conn: conn, buffer: buf)
                    }
                    return
                }
                let bodyEnd = bodyStart + expected
                let bodyChunk = buf.subdata(in: bodyStart..<bodyEnd)
                self.finish(conn: conn, bodyData: bodyChunk)

                let remaining = buf.count - bodyEnd
                if remaining > 0 {
                    // Pipelining is unlikely on localhost; drop extras defensively.
                    print("WebhookListener: ignoring \(remaining) trailing byte(s) after first request")
                }
            } else {
                // No Content-Length (unusual for Ruby Net::HTTP): buffer until the peer closes.
                if !isComplete {
                    self.readRequest(conn: conn, buffer: buf)
                    return
                }
                let bodyChunk = buf.subdata(in: bodyStart..<buf.endIndex)
                self.finish(conn: conn, bodyData: bodyChunk)
            }
        }
    }

    private func finish(conn: NWConnection, bodyData: Data) {
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK"
        conn.send(content: response.data(using: .utf8), completion: .idempotent)
        if let body = String(data: bodyData, encoding: .utf8) {
            onPayload(body)
        }
        conn.cancel()
    }

    /// Parses the first `Content-Length` header (case-insensitive), if present.
    private static func parseContentLength(headerLines: String) -> Int? {
        for line in headerLines.split(separator: "\r\n", omittingEmptySubsequences: false) {
            let lower = line.lowercased()
            guard lower.hasPrefix("content-length:") else { continue }
            let rest = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
            return Int(rest)
        }
        return nil
    }
}

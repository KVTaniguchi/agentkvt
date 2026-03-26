import Foundation
import Network

/// Listens on a local TCP port for HTTP POST requests. On each request, fires `onPayload`
/// with the raw request body and immediately responds with 200 OK. Uses Network.framework
/// (zero external dependencies). Intended for LAN-local triggers only.
final class WebhookListener: @unchecked Sendable {
    private let port: NWEndpoint.Port
    let onPayload: @Sendable (String) -> Void
    private var listener: NWListener?

    init(port: UInt16 = 8765, onPayload: @escaping @Sendable (String) -> Void) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.onPayload = onPayload
    }

    func start() {
        guard let listener = try? NWListener(using: .tcp, on: port) else {
            print("WebhookListener: failed to bind on port \(port)")
            return
        }
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let err) = state {
                print("WebhookListener error: \(err)")
            }
        }
        listener.start(queue: .global(qos: .utility))
        self.listener = listener
        print("WebhookListener: listening on port \(port)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .utility))
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, error in
            defer { conn.cancel() }
            guard error == nil, let data, let raw = String(data: data, encoding: .utf8) else { return }

            // Respond immediately so the caller isn't blocked on LLM execution.
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK"
            conn.send(content: response.data(using: .utf8), completion: .idempotent)

            // Split HTTP headers from body on the blank line.
            if let bodyRange = raw.range(of: "\r\n\r\n") {
                let body = String(raw[bodyRange.upperBound...])
                self?.onPayload(body)
            }
        }
    }
}

import Foundation
import Network
import Security

/// TCP (optionally TLS) transport to a dLive MixRack or Surface.
/// All callbacks are delivered on the main queue.
public final class DLiveConnection {
    public enum State: Equatable, Sendable {
        case disconnected
        case connecting
        case connected
        case failed(String)

        public var isActive: Bool { self == .connecting || self == .connected }
    }

    public var onStateChange: ((State) -> Void)?
    /// Raw bytes as received, in order.
    public var onBytes: (([UInt8]) -> Void)?

    public private(set) var state: State = .disconnected {
        didSet {
            let s = state
            DispatchQueue.main.async { self.onStateChange?(s) }
        }
    }

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "dlive.connection")

    public init() {}

    /// - Parameters:
    ///   - useTLS: connect with TLS. The dLive uses a self-signed certificate, so the
    ///     certificate is not validated.
    public func connect(host: String, port: UInt16, useTLS: Bool) {
        disconnect()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            state = .failed("Invalid port")
            return
        }

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        tcp.keepaliveInterval = 2
        tcp.keepaliveCount = 3
        tcp.connectionTimeout = 5

        var tls: NWProtocolTLS.Options? = nil
        if useTLS {
            let t = NWProtocolTLS.Options()
            sec_protocol_options_set_verify_block(t.securityProtocolOptions, { _, _, complete in
                complete(true)
            }, queue)
            tls = t
        }

        let params = NWParameters(tls: tls, tcp: tcp)
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
        connection = conn
        state = .connecting

        conn.stateUpdateHandler = { [weak self, weak conn] newState in
            guard let self, let conn, conn === self.connection else { return }
            switch newState {
            case .ready:
                self.state = .connected
                self.receive(on: conn)
            case .waiting(let err):
                // Usually "connection refused" or no route; don't keep retrying silently.
                self.state = .failed(err.localizedDescription)
                conn.cancel()
                self.connection = nil
            case .failed(let err):
                self.state = .failed(err.localizedDescription)
                self.connection = nil
            case .cancelled:
                if case .failed = self.state {} else { self.state = .disconnected }
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    public func disconnect() {
        queue.sync {
            connection?.stateUpdateHandler = nil
            connection?.cancel()
            connection = nil
        }
        if state != .disconnected { state = .disconnected }
    }

    public func send(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        queue.async { [weak self] in
            guard let self, let conn = self.connection, self.state == .connected else { return }
            conn.send(content: Data(bytes), completion: .contentProcessed { [weak self] error in
                if let error, let self {
                    self.state = .failed("Send failed: \(error.localizedDescription)")
                }
            })
        }
    }

    private func receive(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, conn === self.connection else { return }
            if let data, !data.isEmpty {
                let bytes = [UInt8](data)
                DispatchQueue.main.async { self.onBytes?(bytes) }
            }
            if let error {
                self.state = .failed(error.localizedDescription)
                conn.cancel()
                self.connection = nil
                return
            }
            if isComplete {
                self.state = .failed("Connection closed by mixer")
                conn.cancel()
                self.connection = nil
                return
            }
            self.receive(on: conn)
        }
    }
}

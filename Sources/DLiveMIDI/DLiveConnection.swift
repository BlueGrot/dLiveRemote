#if canImport(Network)
import Foundation
import Network
import Security

/// TCP (optionally TLS + authentication) transport to a dLive MixRack or Surface.
/// All callbacks are delivered on the main queue.
public final class DLiveConnection {
    public enum State: Equatable, Sendable {
        case disconnected
        case connecting
        case authenticating
        case connected
        case failed(String)

        public var isActive: Bool { self == .connecting || self == .authenticating || self == .connected }
    }

    public struct Credentials: Sendable {
        /// UserProfile 00–1F.
        public var profile: UInt8
        public var password: String
        public init(profile: UInt8, password: String) {
            self.profile = profile
            self.password = password
        }
    }

    public var onStateChange: ((State) -> Void)?
    /// Raw MIDI bytes as received, in order (the "AuthOK" reply is stripped).
    public var onBytes: (([UInt8]) -> Void)?

    // Everything below is only touched on `queue`.
    private var connection: NWConnection?
    private var authBuffer: [UInt8]? = nil
    private var internalState: State = .disconnected
    private let queue = DispatchQueue(label: "dlive.connection")

    public init() {}

    private func setState(_ s: State) {
        internalState = s
        DispatchQueue.main.async { self.onStateChange?(s) }
    }

    /// - Parameter credentials: when using TLS, sent as the first data on the socket
    ///   ("Authentication" in the V2.0 spec). Ignored for plain TCP.
    public func connect(host: String, port: UInt16, useTLS: Bool, credentials: Credentials?) {
        queue.async { self.startConnection(host: host, port: port, useTLS: useTLS, credentials: credentials) }
    }

    public func disconnect() {
        queue.async {
            self.teardown()
            self.setState(.disconnected)
        }
    }

    public func send(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        queue.async {
            guard let conn = self.connection, self.internalState == .connected else { return }
            conn.send(content: Data(bytes), completion: .contentProcessed { [weak self] error in
                guard let self, let error else { return }
                self.queue.async { self.fail("Send failed: \(error.localizedDescription)") }
            })
        }
    }

    // MARK: - Private (on queue)

    private func teardown() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        authBuffer = nil
    }

    private func fail(_ message: String) {
        guard connection != nil else { return }
        teardown()
        setState(.failed(message))
    }

    private func startConnection(host: String, port: UInt16, useTLS: Bool, credentials: Credentials?) {
        teardown()
        guard let nwPort = NWEndpoint.Port(rawValue: port), !host.isEmpty else {
            setState(.failed("Invalid host or port"))
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
            // dLive presents a self-signed certificate.
            sec_protocol_options_set_verify_block(t.securityProtocolOptions, { _, _, complete in
                complete(true)
            }, queue)
            tls = t
        }

        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort,
                                using: NWParameters(tls: tls, tcp: tcp))
        connection = conn
        setState(.connecting)

        conn.stateUpdateHandler = { [weak self, weak conn] newState in
            guard let self, let conn, conn === self.connection else { return }
            switch newState {
            case .ready:
                if useTLS, let credentials {
                    self.authBuffer = []
                    self.setState(.authenticating)
                    let msg = DLive.authMessage(profile: credentials.profile, password: credentials.password)
                    conn.send(content: Data(msg), completion: .contentProcessed { _ in })
                } else {
                    self.setState(.connected)
                }
                self.receive(on: conn)
            case .waiting(let err):
                self.fail(err.localizedDescription)
            case .failed(let err):
                self.fail(err.localizedDescription)
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func receive(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, conn === self.connection else { return }
            if let data, !data.isEmpty {
                self.handle([UInt8](data))
            }
            if let error {
                self.fail(error.localizedDescription)
                return
            }
            if isComplete {
                self.fail(self.internalState == .authenticating
                          ? "Authentication failed (wrong user profile or password)"
                          : "Connection closed by mixer")
                return
            }
            self.receive(on: conn)
        }
    }

    private func handle(_ bytes: [UInt8]) {
        guard var buf = authBuffer else {
            DispatchQueue.main.async { self.onBytes?(bytes) }
            return
        }
        buf += bytes
        let ok = DLive.authOK
        if buf.count < ok.count {
            guard Array(ok.prefix(buf.count)) == buf else {
                fail("Unexpected authentication reply")
                return
            }
            authBuffer = buf
            return
        }
        guard Array(buf.prefix(ok.count)) == ok else {
            fail("Unexpected authentication reply")
            return
        }
        authBuffer = nil
        setState(.connected)
        let rest = Array(buf.dropFirst(ok.count))
        if !rest.isEmpty {
            DispatchQueue.main.async { self.onBytes?(rest) }
        }
    }
}
#endif

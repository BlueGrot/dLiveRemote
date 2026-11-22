import Foundation
import Network
import DLiveMIDI

/// Sends OSC messages over UDP.
final class OSCSender {
    private let connection: NWConnection
    let host: String
    let port: UInt16

    init?(host: String, port: UInt16) {
        guard !host.isEmpty, let p = NWEndpoint.Port(rawValue: port) else { return nil }
        self.host = host
        self.port = port
        connection = NWConnection(host: NWEndpoint.Host(host), port: p, using: .udp)
        connection.start(queue: DispatchQueue(label: "dlive.osc"))
    }

    deinit { connection.cancel() }

    func send(_ msg: OSCMessage) {
        connection.send(content: Data(msg.encoded()), completion: .idempotent)
    }
}

/// The mixer → Mac forwarding path. `process` runs on the network connection's queue,
/// so MIDI reaches other apps without waiting for the main (UI) thread.
final class BridgeEngine {
    let midi: CoreMIDIBridge

    private let lock = NSLock()
    // Guarded by `lock`:
    private var pendingSettings: BridgeSettings
    private var pendingBase: UInt8
    private var settingsChanged = true
    private var resetRequested = false
    private var enabled = true
    private var forwarded = 0
    private var lastRx: Date?

    // Only touched on the connection queue:
    private var parser = MIDIStreamParser()
    private var router: BridgeRouter
    private var osc: OSCSender?

    init(portName: String, settings: BridgeSettings, base: UInt8) {
        midi = CoreMIDIBridge(name: portName)
        pendingSettings = settings
        pendingBase = base
        router = BridgeRouter(settings: settings, base: base)
        applyPorts(settings)
    }

    /// Call on the main thread whenever settings change.
    func update(settings: BridgeSettings, base: UInt8, enabled: Bool) {
        lock.lock()
        pendingSettings = settings
        pendingBase = base
        self.enabled = enabled
        settingsChanged = true
        lock.unlock()
        applyPorts(settings)
    }

    /// Call when a new connection starts (clears parser / NRPN state).
    func reset() {
        lock.lock(); resetRequested = true; lock.unlock()
    }

    var stats: (forwarded: Int, lastRx: Date?) {
        lock.lock(); defer { lock.unlock() }
        return (forwarded, lastRx)
    }

    private func applyPorts(_ s: BridgeSettings) {
        let name = midi.baseName
        var ports: [BridgePort: String] = [.main: name]
        if s.splitPorts {
            for c in MessageCategory.allCases where s.forwardedCategories.contains(c) {
                ports[.category(c)] = "\(name) \(c.portSuffix)"
            }
        }
        if s.msc.enabled { ports[.showControl] = "\(name) MSC" }
        if s.mackie.enabled {
            for bank in 0..<4 { ports[.mackie(bank)] = "\(name) Mackie \(bank * 8 + 1)-\(bank * 8 + 8)" }
        }
        midi.setSources(ports)
    }

    /// Runs on the connection queue for every chunk of bytes from the mixer.
    func process(_ bytes: [UInt8]) {
        lock.lock()
        lastRx = Date()
        let on = enabled
        var newSettings: BridgeSettings? = nil
        var newBase: UInt8 = 0
        if settingsChanged {
            newSettings = pendingSettings
            newBase = pendingBase
            settingsChanged = false
        }
        let reset = resetRequested
        resetRequested = false
        lock.unlock()

        if reset {
            parser = MIDIStreamParser()
            router = BridgeRouter(settings: router.settings, base: router.base)
        }
        if let s = newSettings {
            router.settings = s
            router.base = newBase
            if s.osc.enabled {
                if osc?.host != s.osc.host || osc?.port != s.osc.port {
                    osc = OSCSender(host: s.osc.host, port: s.osc.port)
                }
            } else {
                osc = nil
            }
        }
        guard on else { return }

        var count = 0
        for msg in parser.feed(bytes) {
            for out in router.process(msg) {
                switch out {
                case let .midi(port, m):
                    if midi.publish(m, on: port), port == .main { count += 1 }
                case let .osc(o):
                    osc?.send(o)
                }
            }
        }
        if count > 0 {
            lock.lock(); forwarded += count; lock.unlock()
        }
    }
}

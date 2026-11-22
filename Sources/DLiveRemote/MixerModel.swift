import Foundation
import SwiftUI
import DLiveMIDI

struct StripState: Equatable {
    var level: UInt8 = 0
    var muted = false
    var name = ""
    var colour: UInt8 = 0
}

struct LogEntry: Identifiable {
    enum Direction { case tx, rx }
    let id = UUID()
    let time = Date()
    let direction: Direction
    let hex: String
    let text: String
}

@MainActor
final class MixerModel: ObservableObject {
    // Connection settings (persisted)
    @Published var host: String = UserDefaults.standard.string(forKey: "host") ?? "192.168.1.70" {
        didSet { UserDefaults.standard.set(host, forKey: "host") }
    }
    @Published var port: Int = (UserDefaults.standard.object(forKey: "port") as? Int) ?? Int(DLive.tcpPort) {
        didSet { UserDefaults.standard.set(port, forKey: "port") }
    }
    @Published var useTLS: Bool = UserDefaults.standard.bool(forKey: "useTLS") {
        didSet { UserDefaults.standard.set(useTLS, forKey: "useTLS") }
    }
    /// 1-based base MIDI channel N as set on the dLive (Utility > Control > MIDI). N...N+4 are used.
    @Published var baseChannel: Int = (UserDefaults.standard.object(forKey: "baseChannel") as? Int) ?? 12 {
        didSet {
            UserDefaults.standard.set(baseChannel, forKey: "baseChannel")
            decoder.base = baseByte
        }
    }

    @Published private(set) var connectionState: DLiveConnection.State = .disconnected
    @Published var strips: [ChannelAddress: StripState] = [:]
    @Published var selectedKind: ChannelKind = .input
    @Published private(set) var log: [LogEntry] = []
    @Published var logPaused = false
    @Published var lastScene: Int?

    private let connection = DLiveConnection()
    private var parser = MIDIStreamParser()
    private var decoder: DLiveDecoder
    private let maxLog = 2000

    var baseByte: UInt8 { UInt8(max(1, min(12, baseChannel)) - 1) }

    init() {
        decoder = DLiveDecoder(base: 0)
        decoder.base = baseByte
        connection.onStateChange = { [weak self] s in
            self?.connectionState = s
        }
        connection.onBytes = { [weak self] bytes in
            self?.receive(bytes)
        }
    }

    // MARK: Connection

    func connect() {
        parser = MIDIStreamParser()
        decoder = DLiveDecoder(base: baseByte)
        connection.connect(host: host.trimmingCharacters(in: .whitespaces),
                           port: UInt16(clamping: port),
                           useTLS: useTLS)
    }

    func disconnect() { connection.disconnect() }

    // MARK: State access

    func state(_ a: ChannelAddress) -> StripState { strips[a] ?? StripState() }

    func displayName(_ a: ChannelAddress) -> String {
        let n = state(a).name
        return n.isEmpty ? a.description : n
    }

    // MARK: Sending

    func send(_ cmd: DLiveCommand) {
        let bytes = cmd.encode(base: baseByte)
        connection.send(bytes)
        appendLog(.tx, bytes, cmd.description)
        apply(cmd)
    }

    func sendRaw(_ bytes: [UInt8]) {
        connection.send(bytes)
        appendLog(.tx, bytes, "raw")
    }

    func setLevel(_ a: ChannelAddress, _ v: UInt8) {
        guard state(a).level != v else { return }
        send(.level(a, v))
    }

    func toggleMute(_ a: ChannelAddress) { send(.mute(a, !state(a).muted)) }

    /// Ask the mixer for name, colour, level and mute of every channel of a kind.
    func refresh(_ kind: ChannelKind) {
        for i in 0..<kind.count {
            let a = ChannelAddress(kind, i)
            var cmds: [DLiveCommand] = []
            if kind.hasNameAndColour { cmds += [.getName(a), .getColour(a)] }
            if kind.hasFader { cmds.append(.getLevel(a)) }
            cmds.append(.getMute(a))
            for c in cmds { send(c) }
        }
    }

    /// Optimistically mirror our own changes so the UI follows immediately.
    private func apply(_ cmd: DLiveCommand) {
        switch cmd {
        case let .mute(a, on): strips[a, default: StripState()].muted = on
        case let .level(a, v): strips[a, default: StripState()].level = v
        case let .setName(a, n): strips[a, default: StripState()].name = String(decoding: DLiveCommand.nameBytes(n), as: UTF8.self)
        case let .setColour(a, c): strips[a, default: StripState()].colour = c.rawValue
        case let .recallScene(s): lastScene = s
        default: break
        }
    }

    // MARK: Receiving

    private func receive(_ bytes: [UInt8]) {
        for msg in parser.feed(bytes) {
            let event = decoder.decode(msg)
            if case .system = msg { continue }
            appendLog(.rx, msg.bytes, event?.description ?? "(partial)")
            if let event { apply(event) }
        }
    }

    private func apply(_ e: DLiveEvent) {
        switch e {
        case let .mute(a, on): strips[a, default: StripState()].muted = on
        case let .level(a, v): strips[a, default: StripState()].level = v
        case let .name(a, n): strips[a, default: StripState()].name = n
        case let .colour(a, c): strips[a, default: StripState()].colour = c
        case let .sceneRecalled(s): lastScene = s
        default: break
        }
    }

    // MARK: Log

    private func appendLog(_ dir: LogEntry.Direction, _ bytes: [UInt8], _ text: String) {
        guard !logPaused else { return }
        log.append(LogEntry(direction: dir, hex: Hex.string(bytes), text: text))
        if log.count > maxLog { log.removeFirst(log.count - maxLog) }
    }

    func clearLog() { log.removeAll() }
}

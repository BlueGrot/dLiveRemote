import Foundation
import SwiftUI
import DLiveMIDI

struct StripState: Equatable {
    var level: UInt8 = 0
    var muted = false
    var name = ""
    var colour: UInt8 = 0
    var mainAssigned: Bool? = nil
    var hpfOn: Bool? = nil
}

struct PreampState: Equatable {
    var gain: UInt8 = 0
    var pad = false
    var phantom = false
}

struct LogEntry: Identifiable {
    enum Direction { case tx, rx }
    let id = UUID()
    let time = Date()
    let direction: Direction
    let hex: String
    let text: String
    let isPartial: Bool
}

enum Page: Hashable, Identifiable {
    case channels(ChannelKind)
    case preamps
    var id: String {
        switch self {
        case .channels(let k): return k.rawValue
        case .preamps: return "preamps"
        }
    }
    var title: String {
        switch self {
        case .channels(let k): return k.displayName
        case .preamps: return "Preamps"
        }
    }
}

@MainActor
final class MixerModel: ObservableObject {
    // MARK: Connection settings (persisted, except the password)

    @Published var host: String = UserDefaults.standard.string(forKey: "host") ?? "192.168.1.70" {
        didSet { UserDefaults.standard.set(host, forKey: "host") }
    }
    @Published var target: DLive.Target = DLive.Target(rawValue: UserDefaults.standard.string(forKey: "target") ?? "") ?? .mixRack {
        didSet { UserDefaults.standard.set(target.rawValue, forKey: "target") }
    }
    @Published var useTLS: Bool = UserDefaults.standard.bool(forKey: "useTLS") {
        didSet { UserDefaults.standard.set(useTLS, forKey: "useTLS") }
    }
    /// UserProfile 0–31 (sent as 00–1F) for TLS authentication.
    @Published var userProfile: Int = UserDefaults.standard.integer(forKey: "userProfile") {
        didSet { UserDefaults.standard.set(userProfile, forKey: "userProfile") }
    }
    @Published var password: String = ""
    /// 1-based base MIDI channel N as set in Utility / Control / MIDI. N…N+4 are used.
    @Published var baseChannel: Int = (UserDefaults.standard.object(forKey: "baseChannel") as? Int) ?? 12 {
        didSet {
            UserDefaults.standard.set(baseChannel, forKey: "baseChannel")
            decoder.base = baseByte
        }
    }

    /// Request names/levels/mutes after connecting. Off by default: the replies would
    /// also be forwarded to Mac apps listening on the virtual MIDI port.
    @Published var refreshOnConnect: Bool = UserDefaults.standard.bool(forKey: "refreshOnConnect") {
        didSet { UserDefaults.standard.set(refreshOnConnect, forKey: "refreshOnConnect") }
    }
    @Published var autoReconnect: Bool = (UserDefaults.standard.object(forKey: "autoReconnect") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(autoReconnect, forKey: "autoReconnect") }
    }
    /// Forward everything received from the mixer to the virtual CoreMIDI source.
    @Published var forwardToMac: Bool = (UserDefaults.standard.object(forKey: "forwardToMac") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(forwardToMac, forKey: "forwardToMac") }
    }
    /// Pass messages from Mac apps (virtual destination) to the mixer.
    @Published var forwardFromMac: Bool = (UserDefaults.standard.object(forKey: "forwardFromMac") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(forwardFromMac, forKey: "forwardFromMac") }
    }

    var port: UInt16 { target.port(tls: useTLS) }

    // MARK: Mac MIDI bridge

    static let midiPortName = "dLive"
    let bridge = CoreMIDIBridge(name: MixerModel.midiPortName)
    @Published private(set) var forwardedToMac = 0
    @Published private(set) var receivedFromMac = 0
    @Published private(set) var lastRxTime: Date?

    // MARK: Mixer state

    @Published private(set) var connectionState: DLiveConnection.State = .disconnected
    @Published var strips: [ChannelAddress: StripState] = [:]
    @Published var preamps: [PreampSocket: PreampState] = [:]
    @Published var page: Page = .channels(.input)
    @Published private(set) var log: [LogEntry] = []
    @Published var logPaused = false
    @Published var lastRecall: String?

    private let connection = DLiveConnection()
    private var parser = MIDIStreamParser()
    private var decoder: DLiveDecoder
    private let maxLog = 2000
    private var wantsConnection = false
    private var reconnectWork: DispatchWorkItem?
    private var activity: NSObjectProtocol?

    var baseByte: UInt8 { UInt8(max(1, min(12, baseChannel)) - 1) }
    var isConnected: Bool { connectionState == .connected }

    init() {
        decoder = DLiveDecoder(base: 0)
        decoder.base = baseByte
        connection.onStateChange = { [weak self] s in
            self?.connectionStateChanged(s)
        }
        connection.onBytes = { [weak self] bytes in
            self?.receive(bytes)
        }
        bridge.onMessageFromApps = { [weak self] bytes in
            self?.fromMacApp(bytes)
        }
    }

    private func connectionStateChanged(_ s: DLiveConnection.State) {
        connectionState = s
        switch s {
        case .connected:
            // Keep macOS from App-Napping the bridge while the window is hidden.
            if activity == nil {
                activity = ProcessInfo.processInfo.beginActivity(
                    options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
                    reason: "Bridging dLive MIDI")
            }
            if refreshOnConnect { refresh(page) }
        case .failed:
            endActivity()
            scheduleReconnect()
        case .disconnected:
            endActivity()
        default:
            break
        }
    }

    private func endActivity() {
        if let a = activity { ProcessInfo.processInfo.endActivity(a) }
        activity = nil
    }

    private func scheduleReconnect() {
        guard wantsConnection, autoReconnect else { return }
        reconnectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.wantsConnection, !self.connectionState.isActive else { return }
            self.openConnection()
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    // MARK: Connection

    func connect() {
        wantsConnection = true
        openConnection()
    }

    private func openConnection() {
        reconnectWork?.cancel()
        parser = MIDIStreamParser()
        decoder = DLiveDecoder(base: baseByte)
        let creds = useTLS
            ? DLiveConnection.Credentials(profile: UInt8(max(0, min(31, userProfile))), password: password)
            : nil
        connection.connect(host: host.trimmingCharacters(in: .whitespaces), port: port,
                           useTLS: useTLS, credentials: creds)
    }

    func disconnect() {
        wantsConnection = false
        reconnectWork?.cancel()
        connection.disconnect()
    }

    var isReconnecting: Bool {
        if case .failed = connectionState { return wantsConnection && autoReconnect }
        return false
    }

    // MARK: State access

    func state(_ a: ChannelAddress) -> StripState { strips[a] ?? StripState() }
    func preamp(_ s: PreampSocket) -> PreampState { preamps[s] ?? PreampState() }

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

    func setGain(_ s: PreampSocket, _ v: UInt8) {
        guard preamp(s).gain != v else { return }
        send(.preampGain(s, v))
    }

    func toggleMute(_ a: ChannelAddress) { send(.mute(a, !state(a).muted)) }

    func requestState(_ a: ChannelAddress) {
        if a.kind.hasNameAndColour { send(.getName(a)); send(.getColour(a)) }
        if a.kind.hasFader { send(.getLevel(a)) }
        send(.getMute(a))
        if a.kind.isAssignable { send(.getMainAssign(a)) }
        if a.kind == .input { send(.getHPFOn(a)) }
    }

    /// Ask the mixer for the current state of everything on a page.
    func refresh(_ page: Page) {
        guard isConnected else { return }
        switch page {
        case .channels(let kind):
            for i in 0..<kind.count { requestState(ChannelAddress(kind, i)) }
        case .preamps:
            for mp in 0..<64 {
                let s = PreampSocket(mp: UInt8(mp))
                send(.getPreampGain(s)); send(.getPreampPad(s)); send(.getPreamp48V(s))
            }
        }
    }

    /// Mirror our own changes immediately (the mixer does not echo them back).
    private func apply(_ cmd: DLiveCommand) {
        switch cmd {
        case let .mute(a, on): strips[a, default: StripState()].muted = on
        case let .level(a, v): strips[a, default: StripState()].level = v
        case let .mainAssign(a, on): strips[a, default: StripState()].mainAssigned = on
        case let .hpfOn(a, on): strips[a, default: StripState()].hpfOn = on
        case let .setName(a, n): strips[a, default: StripState()].name = String(decoding: DLiveCommand.nameBytes(n), as: UTF8.self)
        case let .setColour(a, c): strips[a, default: StripState()].colour = c.rawValue
        case let .preampGain(s, v): preamps[s, default: PreampState()].gain = v
        case let .preampPad(s, on): preamps[s, default: PreampState()].pad = on
        case let .preamp48V(s, on): preamps[s, default: PreampState()].phantom = on
        case let .recallScene(s): lastRecall = "Scene \(s)"
        case let .recallCue(id): lastRecall = "Cue \(id)"
        default: break
        }
    }

    // MARK: Receiving

    private func receive(_ bytes: [UInt8]) {
        lastRxTime = Date()
        for msg in parser.feed(bytes) {
            if forwardToMac {
                bridge.publish(msg)
                forwardedToMac += 1
            }
            if case .system = msg { continue }
            let event = decoder.decode(msg)
            appendLog(.rx, msg.bytes, event?.description ?? "(NRPN part / note-off)", partial: event == nil)
            if let event { apply(event) }
        }
    }

    private func apply(_ e: DLiveEvent) {
        switch e {
        case let .mute(a, on): strips[a, default: StripState()].muted = on
        case let .level(a, v): strips[a, default: StripState()].level = v
        case let .mainAssign(a, on): strips[a, default: StripState()].mainAssigned = on
        case let .hpfOn(a, on): strips[a, default: StripState()].hpfOn = on
        case let .name(a, n): strips[a, default: StripState()].name = n
        case let .colour(a, c): strips[a, default: StripState()].colour = c
        case let .preampGain(s, v): preamps[s, default: PreampState()].gain = v
        case let .preampPad(s, on): preamps[s, default: PreampState()].pad = on
        case let .preamp48V(s, on): preamps[s, default: PreampState()].phantom = on
        case let .recall(bank, program):
            let i = Int(bank) * 128 + Int(program)
            lastRecall = target == .mixRack ? "Scene \(i + 1)" : "Cue \(i)"
        default: break
        }
    }

    private func fromMacApp(_ bytes: [UInt8]) {
        receivedFromMac += 1
        guard forwardFromMac else { return }
        connection.send(bytes)
        appendLog(.tx, bytes, "from Mac app")
    }

    // MARK: Log

    private func appendLog(_ dir: LogEntry.Direction, _ bytes: [UInt8], _ text: String, partial: Bool = false) {
        guard !logPaused else { return }
        log.append(LogEntry(direction: dir, hex: Hex.string(bytes), text: text, isPartial: partial))
        if log.count > maxLog { log.removeFirst(log.count - maxLog) }
    }

    func clearLog() { log.removeAll() }
}

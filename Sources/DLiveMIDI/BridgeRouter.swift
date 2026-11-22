import Foundation

// Routing of mixer → Mac MIDI: filtering by category, per-category ports,
// channel remapping, and translation to MIDI Show Control, OSC and Mackie Control.
// Pure Swift so it can be unit-tested anywhere; the app wires it to CoreMIDI and UDP.

/// What kind of message the mixer sent. Used for filtering and per-type ports.
public enum MessageCategory: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    /// Anything on MIDI channels outside N…N+4: MIDI Strips and other custom messages.
    case midiStrips
    /// Bank select + program change on N (scene / cue recall).
    case recalls
    case mutes
    /// Fader level NRPNs (parameter 17).
    case faders
    /// Other NRPNs (main/DCA/mute-group assign, EQ, HPF) and preamp gain pitchbend.
    case processing
    /// SysEx: names, colours, preamp pad/48V, send levels/assigns.
    case sysEx
    /// Other CCs on N…N+4: UFX key/scale, user-defined Go/Next/Previous.
    case control
    /// System common / realtime.
    case system

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .midiStrips: return "MIDI Strips & custom"
        case .recalls: return "Scene / cue recalls"
        case .mutes: return "Mutes"
        case .faders: return "Fader levels"
        case .processing: return "Assigns, EQ, HPF, preamp gain"
        case .sysEx: return "SysEx (names, colours, pad/48V, sends)"
        case .control: return "Other control (UFX key/scale, Go/Next CCs)"
        case .system: return "System / realtime"
        }
    }

    /// Suffix for the per-category virtual port name.
    public var portSuffix: String {
        switch self {
        case .midiStrips: return "Strips"
        case .recalls: return "Scenes"
        case .mutes: return "Mutes"
        case .faders: return "Faders"
        case .processing: return "Processing"
        case .sysEx: return "SysEx"
        case .control: return "Control"
        case .system: return "System"
        }
    }
}

/// Virtual output ports the router can send to.
public enum BridgePort: Hashable, Sendable {
    case main
    case category(MessageCategory)
    case showControl
    /// Mackie Control bank 0…3 (strips 1–8, 9–16, 17–24, 25–32).
    case mackie(Int)
}

public struct MSCSettings: Codable, Equatable, Sendable {
    public var enabled = false
    /// 00–6F device, 7F = all call.
    public var deviceID: UInt8 = 0x7F
    /// Command format: 01 lighting, 10 sound, 7F all types.
    public var commandFormat: UInt8 = 0x7F
    /// Optional cue list sent after the cue number (empty = none).
    public var cueList: String = ""
    public init() {}
}

public struct OSCSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var host = "127.0.0.1"
    public var port: UInt16 = 53000
    /// Sent on scene/cue recall. "{n}" is replaced with the scene number (MixRack)
    /// or Recall Id (Surface). Example for QLab: "/cue/{n}/start".
    public var recallAddress = "/dlive/scene/{n}"
    /// Also send mutes, fader levels, names and MIDI strip messages as /dlive/… messages.
    public var sendEvents = true
    public init() {}
}

/// Translate MIDI Strip messages (as configured on the dLive) to Mackie Control.
public struct MackieSettings: Codable, Equatable, Sendable {
    public var enabled = false
    /// Zero-based MIDI channels the dLive MIDI Strips transmit on (factory: faders B1, rotaries B2, keys 91).
    public var faderChannel: UInt8 = 1
    public var rotaryChannel: UInt8 = 2
    public var keyChannel: UInt8 = 1
    public init() {}
}

public struct BridgeSettings: Codable, Equatable, Sendable {
    public var target: DLive.Target = .mixRack
    public var forwardedCategories: Set<MessageCategory> = Set(MessageCategory.allCases)
    /// Also publish each category on its own port ("dLive Strips", "dLive Scenes", …).
    public var splitPorts = false
    /// Output MIDI channel (0–15) for each input channel (0–15). Identity by default.
    public var channelMap: [UInt8] = Array(0...15)
    public var msc = MSCSettings()
    public var osc = OSCSettings()
    public var mackie = MackieSettings()
    public init() {}

    public var isIdentityMap: Bool { channelMap == Array(0...15) }
}

public enum BridgeOutput: Equatable, Sendable {
    case midi(BridgePort, MIDIMessage)
    case osc(OSCMessage)
}

/// Stateful router. Feed it every complete message from `MIDIStreamParser`, in order.
public struct BridgeRouter {
    public var settings: BridgeSettings
    public var base: UInt8 { didSet { decoder.base = base } }

    private var decoder: DLiveDecoder
    /// NRPN select messages (CC 63/62) held until the data entry (CC 06) shows what they are.
    private var pendingNRPN = [[MIDIMessage]](repeating: [], count: 16)
    /// Bank select on N held until the program change.
    private var pendingBank: MIDIMessage?
    private var lastRotary = [UInt8?](repeating: nil, count: 32)

    public init(settings: BridgeSettings, base: UInt8) {
        self.settings = settings
        self.base = base & 0x0F
        self.decoder = DLiveDecoder(base: base & 0x0F)
    }

    private func offset(_ ch: UInt8) -> UInt8? {
        let o = (Int(ch) - Int(base) + 16) % 16
        return o <= 4 ? UInt8(o) : nil
    }

    public mutating func process(_ msg: MIDIMessage) -> [BridgeOutput] {
        let event = decoder.decode(msg)
        var out: [BridgeOutput] = []

        // A bank select not followed by a program change is flushed on the next message.
        if let bank = pendingBank, !(msg.kindNibble == 0xC0 && msg.channelNibble == base) {
            pendingBank = nil
            emit([bank], .recalls, into: &out)
        }

        switch msg {
        case .system:
            emit([msg], .system, into: &out)
        case .sysEx:
            emit([msg], .sysEx, into: &out)
        case let .channel(status, d1, _):
            let ch = status & 0x0F
            guard let off = offset(ch) else {
                emit([msg], .midiStrips, into: &out)
                if settings.mackie.enabled { out += mackie(msg) }
                if settings.osc.enabled && settings.osc.sendEvents {
                    var args: [OSCMessage.Argument] = msg.bytes.map { .int(Int32($0)) }
                    while args.count < 3 { args.append(.int(0)) }
                    out.append(.osc(OSCMessage("/dlive/midi", args)))
                }
                break
            }
            switch status & 0xF0 {
            case 0x80, 0x90:
                emit([msg], .mutes, into: &out)
            case 0xB0:
                switch d1 {
                case 0x63, 0x62:
                    pendingNRPN[Int(ch)].append(msg)
                case 0x06:
                    let held = pendingNRPN[Int(ch)]
                    pendingNRPN[Int(ch)] = []
                    let cat: MessageCategory
                    if case .level = event { cat = .faders } else { cat = .processing }
                    emit(held + [msg], cat, into: &out)
                case 0x00 where off == 0:
                    pendingBank = msg
                default:
                    emit([msg], .control, into: &out)
                }
            case 0xC0 where off == 0:
                var msgs = [msg]
                if let bank = pendingBank { msgs.insert(bank, at: 0); pendingBank = nil }
                emit(msgs, .recalls, into: &out)
            case 0xE0 where off == 0:
                emit([msg], .processing, into: &out)
            default:
                emit([msg], .control, into: &out)
            }
        }

        if let event { out += translate(event) }
        return out
    }

    // MARK: Forwarding

    private func remap(_ m: MIDIMessage) -> MIDIMessage {
        guard case let .channel(status, d1, d2) = m, !settings.isIdentityMap, settings.channelMap.count == 16 else { return m }
        return .channel(status: (status & 0xF0) | (settings.channelMap[Int(status & 0x0F)] & 0x0F), data1: d1, data2: d2)
    }

    private func emit(_ msgs: [MIDIMessage], _ cat: MessageCategory, into out: inout [BridgeOutput]) {
        guard settings.forwardedCategories.contains(cat) else { return }
        for m in msgs {
            let r = remap(m)
            out.append(.midi(.main, r))
            if settings.splitPorts { out.append(.midi(.category(cat), r)) }
        }
    }

    // MARK: Translation (MSC / OSC)

    private func translate(_ e: DLiveEvent) -> [BridgeOutput] {
        var out: [BridgeOutput] = []
        let osc = settings.osc.enabled
        let events = osc && settings.osc.sendEvents
        switch e {
        case let .recall(bank, program):
            let index = Int(bank) * 128 + Int(program)
            let number = settings.target == .mixRack ? index + 1 : index
            if settings.msc.enabled { out.append(.midi(.showControl, .sysEx(Self.mscGo(number, settings.msc)))) }
            if osc {
                let template = settings.osc.recallAddress
                let addr = template.replacingOccurrences(of: "{n}", with: String(number))
                // Without a {n} placeholder, send the number as an argument instead.
                out.append(.osc(OSCMessage(addr, template.contains("{n}") ? [] : [.int(Int32(number))])))
            }
        case let .mute(a, on) where events:
            out.append(.osc(OSCMessage("/dlive/mute/\(a.kind.rawValue)/\(a.number)", [.int(on ? 1 : 0)])))
        case let .level(a, v) where events:
            let db = FaderLaw.dB(from: v).map { Float($0) } ?? -144
            out.append(.osc(OSCMessage("/dlive/fader/\(a.kind.rawValue)/\(a.number)", [.int(Int32(v)), .float(db)])))
        case let .name(a, n) where events:
            out.append(.osc(OSCMessage("/dlive/name/\(a.kind.rawValue)/\(a.number)", [.string(n)])))
        default:
            break
        }
        return out
    }

    /// MIDI Show Control GO: F0 7F <device> 02 <format> 01 <cue ascii> [00 <list ascii>] F7
    public static func mscGo(_ cue: Int, _ s: MSCSettings) -> [UInt8] {
        var b: [UInt8] = [0xF0, 0x7F, s.deviceID & 0x7F, 0x02, s.commandFormat & 0x7F, 0x01]
        b += Array(String(cue).utf8)
        let list = s.cueList.filter { $0.isASCII && ($0.isNumber || $0 == ".") }
        if !list.isEmpty { b += [0x00] + Array(list.utf8) }
        return b + [0xF7]
    }

    // MARK: Mackie Control

    private mutating func mackie(_ msg: MIDIMessage) -> [BridgeOutput] {
        guard case let .channel(status, d1, d2) = msg else { return [] }
        let ch = status & 0x0F
        let kind = status & 0xF0
        let mk = settings.mackie
        var out: [BridgeOutput] = []

        // Fader: CC 00–1F on fader channel → pitchbend on MCU channel strip%8
        if kind == 0xB0, ch == mk.faderChannel, d1 < 0x20, let v = d2 {
            let strip = Int(d1)
            let v14 = (Int(v) << 7) | Int(v)
            out.append(.midi(.mackie(strip / 8), .channel(status: 0xE0 | UInt8(strip % 8),
                                                         data1: UInt8(v14 & 0x7F), data2: UInt8(v14 >> 7))))
        }
        // Pan rotary: CC 20–3F on rotary channel → relative V-Pot CC 10+strip%8
        if kind == 0xB0, ch == mk.rotaryChannel, d1 >= 0x20, d1 < 0x40, let v = d2 {
            let strip = Int(d1 - 0x20)
            if let last = lastRotary[strip], last != v {
                let delta = Int(v) - Int(last)
                let mag = UInt8(min(0x3F, abs(delta)))
                let value = delta > 0 ? mag : 0x40 | mag
                out.append(.midi(.mackie(strip / 8), .channel(status: 0xB0, data1: 0x10 + UInt8(strip % 8), data2: value)))
            }
            lastRotary[strip] = v
        }
        // Keys: mute 00–1F, mix 20–3F, PAFL 40–5F on key channel → MCU mute / select / solo
        if (kind == 0x90 || kind == 0x80), ch == mk.keyChannel, d1 < 0x60 {
            let strip = Int(d1 & 0x1F)
            let base: UInt8
            switch d1 >> 5 {
            case 0: base = 0x10  // mute
            case 1: base = 0x18  // select
            default: base = 0x08 // solo
            }
            let pressed = kind == 0x90 && (d2 ?? 0) > 0
            out.append(.midi(.mackie(strip / 8), .channel(status: 0x90, data1: base + UInt8(strip % 8), data2: pressed ? 0x7F : 0x00)))
        }
        return out
    }
}

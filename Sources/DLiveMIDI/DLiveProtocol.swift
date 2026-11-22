import Foundation

// MARK: - Constants
//
// Everything byte-level about the dLive protocol lives in this file so it can be checked
// against "dLive MIDI Over TCP/IP Protocol V2.0" in one place.
//
// ⚠️ Values marked UNVERIFIED were written from knowledge of the A&H protocol family and
// could not be checked against the V2.0 PDF while this was written. Confirm them.

public enum DLive {
    /// Unencrypted MIDI over TCP port on the MixRack / Surface.
    public static let tcpPort: UInt16 = 51328
    /// TLS (authenticated) MIDI over TCP port added in protocol V2.0. UNVERIFIED.
    public static let tlsPort: UInt16 = 51329

    /// SysEx header: F0, Allen & Heath ID 00 00 1A, dLive 50 10, major 01, minor 00.
    public static let sysExHeader: [UInt8] = [0xF0, 0x00, 0x00, 0x1A, 0x50, 0x10, 0x01, 0x00]

    /// NRPN parameter numbers (sent as CC 0x62 value).
    public enum NRPN {
        public static let faderLevel: UInt8 = 0x17
        public static let dcaMuteGroupAssign: UInt8 = 0x40
        public static let preampGain: UInt8 = 0x19   // UNVERIFIED
        public static let preampPad: UInt8 = 0x1A    // UNVERIFIED
        public static let preamp48V: UInt8 = 0x1B    // UNVERIFIED
    }

    /// SysEx function bytes (byte after 0N).
    public enum SysExFn {
        public static let getName: UInt8 = 0x01
        public static let nameReply: UInt8 = 0x02
        public static let setName: UInt8 = 0x03
        public static let getColour: UInt8 = 0x04
        public static let colourReply: UInt8 = 0x05
        public static let getParam: UInt8 = 0x05     // followed by 0B 17 (level) or 09 (mute)
        public static let setColour: UInt8 = 0x06
        public static let sendLevel: UInt8 = 0x0D
    }
}

// MARK: - Channel addressing

/// The kinds of processing channel addressable over MIDI.
/// `midiOffset` is added to the base MIDI channel N; `firstCH` is the CH byte of item 1.
public enum ChannelKind: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case input
    case monoGroup, stereoGroup
    case monoAux, stereoAux
    case monoMatrix, stereoMatrix
    case monoFXSend, stereoFXSend, fxReturn
    case main
    case dca
    case muteGroup
    case stereoUFXSend, stereoUFXReturn

    public var id: String { rawValue }

    public var midiOffset: UInt8 {
        switch self {
        case .input: return 0
        case .monoGroup, .stereoGroup: return 1
        case .monoAux, .stereoAux: return 2
        case .monoMatrix, .stereoMatrix: return 3
        default: return 4
        }
    }

    public var firstCH: UInt8 {
        switch self {
        case .input, .monoGroup, .monoAux, .monoMatrix, .monoFXSend: return 0x00
        case .stereoGroup, .stereoAux, .stereoMatrix: return 0x40
        case .stereoFXSend: return 0x10
        case .fxReturn: return 0x20
        case .main: return 0x30
        case .dca: return 0x36
        case .muteGroup: return 0x4E
        case .stereoUFXSend: return 0x56
        case .stereoUFXReturn: return 0x5E
        }
    }

    public var count: Int {
        switch self {
        case .input: return 128
        case .monoGroup, .monoAux, .monoMatrix: return 62
        case .stereoGroup, .stereoAux, .stereoMatrix: return 31
        case .monoFXSend, .stereoFXSend, .fxReturn: return 16
        case .main: return 6
        case .dca: return 24
        case .muteGroup, .stereoUFXSend, .stereoUFXReturn: return 8
        }
    }

    public var displayName: String {
        switch self {
        case .input: return "Inputs"
        case .monoGroup: return "Mono Groups"
        case .stereoGroup: return "Stereo Groups"
        case .monoAux: return "Mono Auxes"
        case .stereoAux: return "Stereo Auxes"
        case .monoMatrix: return "Mono Matrices"
        case .stereoMatrix: return "Stereo Matrices"
        case .monoFXSend: return "Mono FX Sends"
        case .stereoFXSend: return "Stereo FX Sends"
        case .fxReturn: return "FX Returns"
        case .main: return "Mains"
        case .dca: return "DCAs"
        case .muteGroup: return "Mute Groups"
        case .stereoUFXSend: return "UFX Sends"
        case .stereoUFXReturn: return "UFX Returns"
        }
    }

    public var shortPrefix: String {
        switch self {
        case .input: return "Ip"
        case .monoGroup: return "Grp"
        case .stereoGroup: return "StGrp"
        case .monoAux: return "Aux"
        case .stereoAux: return "StAux"
        case .monoMatrix: return "Mtx"
        case .stereoMatrix: return "StMtx"
        case .monoFXSend: return "FXS"
        case .stereoFXSend: return "StFXS"
        case .fxReturn: return "FXR"
        case .main: return "Main"
        case .dca: return "DCA"
        case .muteGroup: return "MG"
        case .stereoUFXSend: return "UFXS"
        case .stereoUFXReturn: return "UFXR"
        }
    }

    public var hasFader: Bool { self != .muteGroup }
    public var hasNameAndColour: Bool { self != .muteGroup }
    /// Can be the destination of a send-level message.
    public var isSendDestination: Bool {
        switch self {
        case .monoAux, .stereoAux, .monoMatrix, .stereoMatrix, .monoFXSend, .stereoFXSend, .monoGroup, .stereoGroup:
            return true
        default: return false
        }
    }
}

/// A specific channel, e.g. Input 12. `index` is zero-based.
public struct ChannelAddress: Hashable, Codable, Sendable, CustomStringConvertible {
    public let kind: ChannelKind
    public let index: Int

    public init(_ kind: ChannelKind, _ index: Int) {
        precondition(index >= 0 && index < kind.count, "index out of range for \(kind)")
        self.kind = kind
        self.index = index
    }

    /// 1-based number as shown on the console.
    public var number: Int { index + 1 }
    public var chByte: UInt8 { kind.firstCH + UInt8(index) }
    public func midiChannel(base: UInt8) -> UInt8 { (base + kind.midiOffset) & 0x0F }

    public var description: String { "\(kind.shortPrefix) \(number)" }

    /// Reverse lookup from MIDI channel offset (0...4) and CH byte.
    public static func from(offset: UInt8, ch: UInt8) -> ChannelAddress? {
        for kind in ChannelKind.allCases where kind.midiOffset == offset {
            let lo = Int(kind.firstCH)
            if Int(ch) >= lo && Int(ch) < lo + kind.count {
                return ChannelAddress(kind, Int(ch) - lo)
            }
        }
        return nil
    }
}

// MARK: - Values

public enum FaderLaw {
    /// 0x7F = +10 dB, 0x6B = 0 dB, 0x00 = -inf. Approximately linear in dB between.
    /// UNVERIFIED in detail: the PDF has a lookup table; this formula hits its anchor points.
    public static func value(fromDB db: Double) -> UInt8 {
        if db <= -54 { return 0 }
        let v = ((db + 54.0) * 127.0 / 64.0).rounded()
        return UInt8(max(1, min(127, v)))
    }

    /// Returns nil for -inf.
    public static func dB(from value: UInt8) -> Double? {
        if value == 0 { return nil }
        return Double(value) * 64.0 / 127.0 - 54.0
    }

    public static func label(for value: UInt8) -> String {
        guard let db = dB(from: value) else { return "-∞" }
        let r = (db * 10).rounded() / 10
        return r > 0 ? String(format: "+%.1f", r) : String(format: "%.1f", r)
    }

    public static let unity: UInt8 = 0x6B
}

/// Channel colour codes. UNVERIFIED mapping.
public enum ChannelColour: UInt8, CaseIterable, Identifiable, Sendable {
    case off = 0, red, green, yellow, blue, purple, lightBlue, white
    public var id: UInt8 { rawValue }
    public var name: String {
        switch self {
        case .off: return "Off"
        case .red: return "Red"
        case .green: return "Green"
        case .yellow: return "Yellow"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .lightBlue: return "Light Blue"
        case .white: return "White"
        }
    }
}

// MARK: - Outgoing commands

public enum DLiveCommand: Equatable, Sendable, CustomStringConvertible {
    case mute(ChannelAddress, Bool)
    case level(ChannelAddress, UInt8)
    /// Send level from a source channel to an aux/matrix/FX/group destination.
    case sendLevel(from: ChannelAddress, to: ChannelAddress, UInt8)
    /// dca: 0...23
    case dcaAssign(ChannelAddress, dca: Int, assigned: Bool)
    /// group: 0...7
    case muteGroupAssign(ChannelAddress, group: Int, assigned: Bool)
    case setName(ChannelAddress, String)
    case setColour(ChannelAddress, ChannelColour)
    case getName(ChannelAddress)
    case getColour(ChannelAddress)
    case getLevel(ChannelAddress)
    case getMute(ChannelAddress)
    /// scene: 1...500
    case recallScene(Int)
    /// socket: 0-based MixRack socket, value 0...127
    case preampGain(socket: Int, UInt8)
    case preampPad(socket: Int, Bool)
    case preamp48V(socket: Int, Bool)
    case raw([UInt8])

    public var description: String {
        switch self {
        case let .mute(a, on): return "\(a) mute \(on ? "ON" : "OFF")"
        case let .level(a, v): return "\(a) level \(FaderLaw.label(for: v)) dB"
        case let .sendLevel(f, t, v): return "\(f) → \(t) send \(FaderLaw.label(for: v)) dB"
        case let .dcaAssign(a, d, on): return "\(a) \(on ? "assign to" : "unassign from") DCA \(d + 1)"
        case let .muteGroupAssign(a, g, on): return "\(a) \(on ? "assign to" : "unassign from") MG \(g + 1)"
        case let .setName(a, n): return "\(a) name \"\(n)\""
        case let .setColour(a, c): return "\(a) colour \(c.name)"
        case let .getName(a): return "get name \(a)"
        case let .getColour(a): return "get colour \(a)"
        case let .getLevel(a): return "get level \(a)"
        case let .getMute(a): return "get mute \(a)"
        case let .recallScene(s): return "recall scene \(s)"
        case let .preampGain(s, v): return "socket \(s + 1) gain \(v)"
        case let .preampPad(s, on): return "socket \(s + 1) pad \(on ? "ON" : "OFF")"
        case let .preamp48V(s, on): return "socket \(s + 1) 48V \(on ? "ON" : "OFF")"
        case .raw: return "raw"
        }
    }

    /// Encode to bytes. `base` is the zero-based base MIDI channel N (0 = MIDI channel 1).
    public func encode(base: UInt8) -> [UInt8] {
        let N = base & 0x0F
        func nrpn(_ ch: UInt8, midi: UInt8, param: UInt8, value: UInt8) -> [UInt8] {
            let b = 0xB0 | (midi & 0x0F)
            return [b, 0x63, ch & 0x7F, b, 0x62, param & 0x7F, b, 0x06, value & 0x7F]
        }
        func sysex(_ body: [UInt8]) -> [UInt8] {
            DLive.sysExHeader + body.map { $0 & 0x7F } + [0xF7]
        }
        // In SysEx the "0N" byte is the MIDI channel of the addressed channel type.
        func sysN(_ a: ChannelAddress) -> UInt8 { a.midiChannel(base: N) }

        switch self {
        case let .mute(a, on):
            let s = 0x90 | a.midiChannel(base: N)
            return [s, a.chByte, on ? 0x7F : 0x3F, s, a.chByte, 0x00]
        case let .level(a, v):
            return nrpn(a.chByte, midi: a.midiChannel(base: N), param: DLive.NRPN.faderLevel, value: v)
        case let .sendLevel(f, t, v):
            return sysex([sysN(f), DLive.SysExFn.sendLevel, f.chByte, t.midiChannel(base: N), t.chByte, v])
        case let .dcaAssign(a, d, on):
            let v = UInt8(d) + (on ? 0x40 : 0x00)
            return nrpn(a.chByte, midi: a.midiChannel(base: N), param: DLive.NRPN.dcaMuteGroupAssign, value: v)
        case let .muteGroupAssign(a, g, on):
            let v = UInt8(g) + (on ? 0x58 : 0x18)
            return nrpn(a.chByte, midi: a.midiChannel(base: N), param: DLive.NRPN.dcaMuteGroupAssign, value: v)
        case let .setName(a, name):
            return sysex([sysN(a), DLive.SysExFn.setName, a.chByte] + Self.nameBytes(name))
        case let .setColour(a, c):
            return sysex([sysN(a), DLive.SysExFn.setColour, a.chByte, c.rawValue])
        case let .getName(a):
            return sysex([sysN(a), DLive.SysExFn.getName, a.chByte])
        case let .getColour(a):
            return sysex([sysN(a), DLive.SysExFn.getColour, a.chByte])
        case let .getLevel(a):
            return sysex([sysN(a), DLive.SysExFn.getParam, 0x0B, DLive.NRPN.faderLevel, a.chByte])
        case let .getMute(a):
            return sysex([sysN(a), DLive.SysExFn.getParam, 0x09, a.chByte])
        case let .recallScene(scene):
            let s = max(1, min(500, scene)) - 1
            return [0xB0 | N, 0x00, UInt8(s / 128), 0xC0 | N, UInt8(s % 128)]
        case let .preampGain(socket, v):
            return nrpn(UInt8(socket), midi: N, param: DLive.NRPN.preampGain, value: v)
        case let .preampPad(socket, on):
            return nrpn(UInt8(socket), midi: N, param: DLive.NRPN.preampPad, value: on ? 0x7F : 0x00)
        case let .preamp48V(socket, on):
            return nrpn(UInt8(socket), midi: N, param: DLive.NRPN.preamp48V, value: on ? 0x7F : 0x00)
        case let .raw(b):
            return b
        }
    }

    /// Names are 7-bit ASCII, max 8 characters.
    public static func nameBytes(_ s: String) -> [UInt8] {
        let ascii = s.unicodeScalars.map { $0.isASCII && $0.value >= 0x20 ? UInt8($0.value) : UInt8(ascii: "?") }
        return Array(ascii.prefix(8))
    }
}

// MARK: - Incoming events

public enum DLiveEvent: Equatable, Sendable, CustomStringConvertible {
    case mute(ChannelAddress, Bool)
    case level(ChannelAddress, UInt8)
    case sendLevel(from: ChannelAddress, to: ChannelAddress, UInt8)
    case dcaAssign(ChannelAddress, dca: Int, assigned: Bool)
    case muteGroupAssign(ChannelAddress, group: Int, assigned: Bool)
    case name(ChannelAddress, String)
    case colour(ChannelAddress, UInt8)
    case sceneRecalled(Int)
    case preampGain(socket: Int, UInt8)
    case preampPad(socket: Int, Bool)
    case preamp48V(socket: Int, Bool)
    case unknown(MIDIMessage)

    public var description: String {
        switch self {
        case let .mute(a, on): return "\(a) mute \(on ? "ON" : "OFF")"
        case let .level(a, v): return "\(a) level \(FaderLaw.label(for: v)) dB"
        case let .sendLevel(f, t, v): return "\(f) → \(t) send \(FaderLaw.label(for: v)) dB"
        case let .dcaAssign(a, d, on): return "\(a) \(on ? "assigned to" : "unassigned from") DCA \(d + 1)"
        case let .muteGroupAssign(a, g, on): return "\(a) \(on ? "assigned to" : "unassigned from") MG \(g + 1)"
        case let .name(a, n): return "\(a) name \"\(n)\""
        case let .colour(a, c): return "\(a) colour \(ChannelColour(rawValue: c)?.name ?? String(c))"
        case let .sceneRecalled(s): return "scene \(s) recalled"
        case let .preampGain(s, v): return "socket \(s + 1) gain \(v)"
        case let .preampPad(s, on): return "socket \(s + 1) pad \(on ? "ON" : "OFF")"
        case let .preamp48V(s, on): return "socket \(s + 1) 48V \(on ? "ON" : "OFF")"
        case .unknown: return "unrecognised"
        }
    }
}

/// Stateful decoder: tracks NRPN parameter selection and scene bank per MIDI channel.
public struct DLiveDecoder {
    public var base: UInt8
    private var nrpnMSB = [UInt8?](repeating: nil, count: 16)
    private var nrpnLSB = [UInt8?](repeating: nil, count: 16)
    private var bank = [UInt8](repeating: 0, count: 16)

    public init(base: UInt8) { self.base = base & 0x0F }

    private func offset(of midiChannel: UInt8) -> UInt8? {
        let o = (Int(midiChannel) - Int(base) + 16) % 16
        return o <= 4 ? UInt8(o) : nil
    }

    public mutating func decode(_ msg: MIDIMessage) -> DLiveEvent? {
        switch msg {
        case let .channel(status, d1, d2):
            let ch = status & 0x0F
            switch status & 0xF0 {
            case 0x90:
                guard let d2, d2 != 0 else { return nil } // the trailing 9N CH 00 note-off
                guard let off = offset(of: ch), let a = ChannelAddress.from(offset: off, ch: d1) else { return .unknown(msg) }
                return .mute(a, d2 >= 0x40)
            case 0xB0:
                guard let d2 else { return nil }
                switch d1 {
                case 0x63: nrpnMSB[Int(ch)] = d2; return nil
                case 0x62: nrpnLSB[Int(ch)] = d2; return nil
                case 0x00: bank[Int(ch)] = d2; return nil
                case 0x06:
                    guard let msb = nrpnMSB[Int(ch)], let lsb = nrpnLSB[Int(ch)] else { return .unknown(msg) }
                    return decodeNRPN(midiChannel: ch, chByte: msb, param: lsb, value: d2) ?? .unknown(msg)
                default:
                    return .unknown(msg)
                }
            case 0xC0:
                guard ch == base else { return .unknown(msg) }
                return .sceneRecalled(Int(bank[Int(ch)]) * 128 + Int(d1) + 1)
            default:
                return .unknown(msg)
            }
        case let .sysEx(bytes):
            return decodeSysEx(bytes) ?? .unknown(msg)
        case .system:
            return nil
        }
    }

    private func decodeNRPN(midiChannel: UInt8, chByte: UInt8, param: UInt8, value: UInt8) -> DLiveEvent? {
        switch param {
        case DLive.NRPN.faderLevel:
            guard let off = offset(of: midiChannel), let a = ChannelAddress.from(offset: off, ch: chByte) else { return nil }
            return .level(a, value)
        case DLive.NRPN.dcaMuteGroupAssign:
            guard let off = offset(of: midiChannel), let a = ChannelAddress.from(offset: off, ch: chByte) else { return nil }
            switch value {
            case 0x00...0x17: return .dcaAssign(a, dca: Int(value), assigned: false)
            case 0x18...0x1F: return .muteGroupAssign(a, group: Int(value - 0x18), assigned: false)
            case 0x40...0x57: return .dcaAssign(a, dca: Int(value - 0x40), assigned: true)
            case 0x58...0x5F: return .muteGroupAssign(a, group: Int(value - 0x58), assigned: true)
            default: return nil
            }
        case DLive.NRPN.preampGain where midiChannel == base:
            return .preampGain(socket: Int(chByte), value)
        case DLive.NRPN.preampPad where midiChannel == base:
            return .preampPad(socket: Int(chByte), value >= 0x40)
        case DLive.NRPN.preamp48V where midiChannel == base:
            return .preamp48V(socket: Int(chByte), value >= 0x40)
        default:
            return nil
        }
    }

    private func decodeSysEx(_ b: [UInt8]) -> DLiveEvent? {
        let h = DLive.sysExHeader
        guard b.count >= h.count + 3, Array(b.prefix(h.count)) == h, b.last == 0xF7 else { return nil }
        let body = Array(b[h.count..<(b.count - 1)])
        guard body.count >= 3, let off = offset(of: body[0] & 0x0F) else { return nil }
        let fn = body[1]
        switch fn {
        case DLive.SysExFn.nameReply, DLive.SysExFn.setName:
            guard let a = ChannelAddress.from(offset: off, ch: body[2]) else { return nil }
            let nameBytes = body.dropFirst(3).filter { $0 != 0 }
            return .name(a, String(decoding: nameBytes, as: UTF8.self))
        case DLive.SysExFn.colourReply where body.count == 4, DLive.SysExFn.setColour where body.count == 4:
            guard let a = ChannelAddress.from(offset: off, ch: body[2]) else { return nil }
            return .colour(a, body[3])
        case DLive.SysExFn.sendLevel where body.count == 6:
            guard let from = ChannelAddress.from(offset: off, ch: body[2]),
                  let toOff = offset(of: body[3] & 0x0F),
                  let to = ChannelAddress.from(offset: toOff, ch: body[4]) else { return nil }
            return .sendLevel(from: from, to: to, body[5])
        default:
            return nil
        }
    }
}

// MARK: - Hex helpers

public enum Hex {
    public static func string(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// Parses "B0 63 01", "b0,63,01", "0xB0 0x63" etc. Returns nil on any invalid token.
    public static func parse(_ s: String) -> [UInt8]? {
        let cleaned = s.replacingOccurrences(of: "0x", with: " ", options: .caseInsensitive)
        let tokens = cleaned.split(whereSeparator: { " ,;\t\n".contains($0) })
        var out: [UInt8] = []
        for t in tokens {
            // Allow runs like "B06301" as well as single bytes.
            guard t.count % 2 == 0 else {
                guard t.count == 1, let v = UInt8(t, radix: 16) else { return nil }
                out.append(v); continue
            }
            var i = t.startIndex
            while i < t.endIndex {
                let j = t.index(i, offsetBy: 2)
                guard let v = UInt8(t[i..<j], radix: 16) else { return nil }
                out.append(v)
                i = j
            }
        }
        return out
    }
}

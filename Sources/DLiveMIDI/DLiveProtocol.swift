import Foundation

// MARK: - Constants
//
// Everything byte-level about the dLive protocol lives in this file.
// Source: "dLive MIDI Over TCP/IP Protocol – Firmware V2.0" (Allen & Heath).
// Section names from the spec are quoted in comments.

public enum DLive {
    /// "To connect to the MixRack / Surface, clients should be configured to use…"
    public enum Target: String, CaseIterable, Identifiable, Codable, Sendable {
        case mixRack, surface
        public var id: String { rawValue }
        public var displayName: String { self == .mixRack ? "MixRack" : "Surface" }
        public func port(tls: Bool) -> UInt16 {
            switch (self, tls) {
            case (.mixRack, false): return 51325
            case (.mixRack, true): return 51327
            case (.surface, false): return 51328
            case (.surface, true): return 51329
            }
        }
    }

    /// "SysEx Header": F0, 00, 00, 1A, 50, 10, MV(01), mV(00)
    public static let sysExHeader: [UInt8] = [0xF0, 0x00, 0x00, 0x1A, 0x50, 0x10, 0x01, 0x00]

    /// "Authentication": after the TLS socket opens, send UserProfile (00–1F) then the password.
    /// The unit answers with the six characters "AuthOK", or drops the connection.
    public static func authMessage(profile: UInt8, password: String) -> [UInt8] {
        [profile & 0x1F] + Array(password.utf8)
    }
    public static let authOK: [UInt8] = Array("AuthOK".utf8)

    /// NRPN parameter IDs (CC 62 value).
    public enum NRPN {
        public static let faderLevel: UInt8 = 0x17
        public static let mainAssign: UInt8 = 0x18
        /// Only used inside "Get Socket Preamp Gain" (the gain itself is sent as Pitchbend).
        public static let preampGain: UInt8 = 0x19
        /// Parametric EQ: 1A–29, four params per band (type, freq, width, gain).
        public static let peqFirst: UInt8 = 0x1A
        public static let hpfFrequency: UInt8 = 0x30
        public static let hpfOn: UInt8 = 0x31
        public static let dcaMuteGroupAssign: UInt8 = 0x40
    }

    /// SysEx function bytes (the byte after 0N).
    public enum SysExFn {
        public static let getName: UInt8 = 0x01
        public static let nameReply: UInt8 = 0x02
        public static let setName: UInt8 = 0x03
        public static let getColour: UInt8 = 0x04
        /// Client→mixer: generic "get" (05, 0B, param, CH / 05, 09, CH / 05, 0F, fn, …).
        /// Mixer→client: colour reply (05, CH, Col).
        public static let get: UInt8 = 0x05
        public static let colourReply: UInt8 = 0x05
        public static let setColour: UInt8 = 0x06
        public static let getPad: UInt8 = 0x07
        public static let padReply: UInt8 = 0x08
        public static let setPad: UInt8 = 0x09
        public static let get48V: UInt8 = 0x0A
        public static let phantomReply: UInt8 = 0x0B
        public static let set48V: UInt8 = 0x0C
        public static let sendLevel: UInt8 = 0x0D
        public static let sendAssign: UInt8 = 0x0E
    }

    /// Control Change numbers on base channel N.
    public enum CC {
        public static let bankSelect: UInt8 = 0x00
        public static let ufxGlobalKey: UInt8 = 0x0C
        public static let ufxGlobalScale: UInt8 = 0x0D
    }
}

// MARK: - Channel addressing

/// "Channel Selection". `midiOffset` is added to base channel N; `firstCH` is the CH of item 1.
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

    /// "Fader levels: Input, Mix master, FX send, FX return, DCA" — mute groups have no fader.
    public var hasFader: Bool { self != .muteGroup }
    public var hasNameAndColour: Bool { self != .muteGroup }
    /// Channels that can be assigned to DCAs / mute groups / main.
    public var isAssignable: Bool { self != .dca && self != .muteGroup && self != .main }
    /// Destinations for "AUX / FX / Matrix Send Level" and "Input to Group / Aux".
    public var isSendDestination: Bool {
        switch self {
        case .monoAux, .stereoAux, .monoMatrix, .stereoMatrix, .monoFXSend, .stereoFXSend,
             .monoGroup, .stereoGroup, .stereoUFXSend:
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

    public var number: Int { index + 1 }
    public var chByte: UInt8 { kind.firstCH + UInt8(index) }
    public func midiChannel(base: UInt8) -> UInt8 { (base + kind.midiOffset) & 0x0F }
    public var description: String { "\(kind.shortPrefix) \(number)" }

    /// Reverse lookup from MIDI channel offset (0…4) and CH byte.
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

/// "Socket Preamp numbers": MixRack sockets 1–64 = 00–3F, DX 1/2 1–32 = 40–5F, DX 3/4 1–32 = 60–7F.
public struct PreampSocket: Hashable, Sendable, CustomStringConvertible {
    public let mp: UInt8
    public init(mp: UInt8) { self.mp = mp & 0x7F }

    public var description: String {
        switch mp {
        case 0x00...0x3F: return "Skt \(Int(mp) + 1)"
        case 0x40...0x5F: return "DX1/2 \(Int(mp) - 0x40 + 1)"
        default: return "DX3/4 \(Int(mp) - 0x60 + 1)"
        }
    }
}

// MARK: - Value laws

public enum FaderLaw {
    /// Spec: LV = [(Gain+54)/64]*7F, -inf = 00, +10 dB = 7F.
    /// The spec's table truncates (e.g. -25 dB = 39, not 3A), so this does too.
    public static func value(fromDB db: Double) -> UInt8 {
        if db < -54 { return 0 }
        let v = ((db + 54.0) / 64.0 * 127.0 + 1e-9).rounded(.down)
        return UInt8(max(0, min(127, v)))
    }

    /// Returns nil for -inf (00).
    public static func dB(from value: UInt8) -> Double? {
        if value == 0 { return nil }
        return Double(value) / 127.0 * 64.0 - 54.0
    }

    public static func label(for value: UInt8) -> String {
        guard let db = dB(from: value) else { return "-∞" }
        let r = (db * 10).rounded() / 10
        return r > 0 ? String(format: "+%.1f", r) : String(format: "%.1f", r)
    }

    /// 0 dB = 6B per the spec table.
    public static let unity: UInt8 = 0x6B
}

public enum PreampGainLaw {
    /// Spec: GV = [(Gain-5)/55]*7F, +5 dB = 00, +60 dB = 7F.
    public static func value(fromDB db: Double) -> UInt8 {
        UInt8(max(0, min(127, ((db - 5.0) / 55.0 * 127.0).rounded())))
    }
    public static func dB(from value: UInt8) -> Double { Double(value) / 127.0 * 55.0 + 5.0 }
    public static func label(for value: UInt8) -> String { String(format: "+%.0f", dB(from: value).rounded()) }
}

/// Parametric EQ / HPF value helpers from the spec.
public enum EQLaw {
    /// "vv For Frequency" 20 Hz – 20 kHz.
    public static func peqFrequency(_ hz: Double) -> UInt8 {
        let v = 127.0 * ((4608.0 * log10(hz / 4.0) / log10(2.0)) - 10699.0) / 45922.0
        return UInt8(max(0, min(127, Int(v))))
    }
    /// "HPF Frequency".
    public static func hpfFrequency(_ hz: Double) -> UInt8 {
        let v = 127.0 * ((4608.0 * log10(hz / 4.0) / log10(2.0)) - 10699.0) / 41314.0
        return UInt8(max(0, min(127, Int(v))))
    }
    /// "vv For Gain": -15…+15 dB.
    public static func peqGain(_ db: Double) -> UInt8 {
        UInt8(max(0, min(127, Int((db + 15.0) * 126.0 / 30.0))))
    }
}

public enum PEQParam: UInt8, CaseIterable, Sendable {
    case type = 0, frequency, width, gain
    public var name: String { ["Type", "Freq", "Width", "Gain"][Int(rawValue)] }
}

/// "Colour" table.
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

public enum UFXKey: UInt8, CaseIterable, Identifiable, Sendable {
    case c = 0, cSharp, d, dSharp, e, f, fSharp, g, gSharp, a, aSharp, b
    public var id: UInt8 { rawValue }
    public var name: String { ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"][Int(rawValue)] }
}

public enum UFXScale: UInt8, CaseIterable, Identifiable, Sendable {
    case major = 0, minor
    public var id: UInt8 { rawValue }
    public var name: String { self == .major ? "Major" : "Minor" }
}

// MARK: - Outgoing commands

public enum DLiveCommand: Equatable, Sendable, CustomStringConvertible {
    case mute(ChannelAddress, Bool)
    case level(ChannelAddress, UInt8)
    case mainAssign(ChannelAddress, Bool)
    /// dca: 0…23
    case dcaAssign(ChannelAddress, dca: Int, assigned: Bool)
    /// group: 0…7
    case muteGroupAssign(ChannelAddress, group: Int, assigned: Bool)
    case sendLevel(from: ChannelAddress, to: ChannelAddress, UInt8)
    case sendAssign(from: ChannelAddress, to: ChannelAddress, Bool)
    case setName(ChannelAddress, String)
    case setColour(ChannelAddress, ChannelColour)
    case preampGain(PreampSocket, UInt8)
    case preampPad(PreampSocket, Bool)
    case preamp48V(PreampSocket, Bool)
    case hpfOn(ChannelAddress, Bool)
    case hpfFrequency(ChannelAddress, UInt8)
    /// band 0…3
    case peq(ChannelAddress, band: Int, PEQParam, UInt8)
    /// MixRack: scene 1…500
    case recallScene(Int)
    /// Surface: cue list Recall Id 0…1999
    case recallCue(Int)
    case ufxKey(UFXKey)
    case ufxScale(UFXScale)
    /// Arbitrary CC on base channel N (e.g. user-defined Go/Next/Previous).
    case controlChange(number: UInt8, value: UInt8)

    case getName(ChannelAddress)
    case getColour(ChannelAddress)
    case getLevel(ChannelAddress)
    case getMute(ChannelAddress)
    case getMainAssign(ChannelAddress)
    case getSendLevel(from: ChannelAddress, to: ChannelAddress)
    case getSendAssign(from: ChannelAddress, to: ChannelAddress)
    case getPreampGain(PreampSocket)
    case getPreampPad(PreampSocket)
    case getPreamp48V(PreampSocket)
    case getHPFOn(ChannelAddress)
    case getHPFFrequency(ChannelAddress)
    case getPEQ(ChannelAddress, band: Int, PEQParam)

    case raw([UInt8])

    public var description: String {
        switch self {
        case let .mute(a, on): return "\(a) mute \(on ? "ON" : "OFF")"
        case let .level(a, v): return "\(a) level \(FaderLaw.label(for: v)) dB"
        case let .mainAssign(a, on): return "\(a) main assign \(on ? "ON" : "OFF")"
        case let .dcaAssign(a, d, on): return "\(a) \(on ? "assign to" : "unassign from") DCA \(d + 1)"
        case let .muteGroupAssign(a, g, on): return "\(a) \(on ? "assign to" : "unassign from") MG \(g + 1)"
        case let .sendLevel(f, t, v): return "\(f) → \(t) send \(FaderLaw.label(for: v)) dB"
        case let .sendAssign(f, t, on): return "\(f) → \(t) assign \(on ? "ON" : "OFF")"
        case let .setName(a, n): return "\(a) name \"\(n)\""
        case let .setColour(a, c): return "\(a) colour \(c.name)"
        case let .preampGain(s, v): return "\(s) gain \(PreampGainLaw.label(for: v)) dB"
        case let .preampPad(s, on): return "\(s) pad \(on ? "ON" : "OFF")"
        case let .preamp48V(s, on): return "\(s) 48V \(on ? "ON" : "OFF")"
        case let .hpfOn(a, on): return "\(a) HPF \(on ? "ON" : "OFF")"
        case let .hpfFrequency(a, v): return "\(a) HPF freq \(v)"
        case let .peq(a, b, p, v): return "\(a) PEQ band \(b) \(p.name) \(v)"
        case let .recallScene(s): return "recall scene \(s)"
        case let .recallCue(id): return "recall cue id \(id)"
        case let .ufxKey(k): return "UFX key \(k.name)"
        case let .ufxScale(s): return "UFX scale \(s.name)"
        case let .controlChange(n, v): return String(format: "CC %02X = %02X", n, v)
        case let .getName(a): return "get name \(a)"
        case let .getColour(a): return "get colour \(a)"
        case let .getLevel(a): return "get level \(a)"
        case let .getMute(a): return "get mute \(a)"
        case let .getMainAssign(a): return "get main assign \(a)"
        case let .getSendLevel(f, t): return "get send level \(f) → \(t)"
        case let .getSendAssign(f, t): return "get send assign \(f) → \(t)"
        case let .getPreampGain(s): return "get gain \(s)"
        case let .getPreampPad(s): return "get pad \(s)"
        case let .getPreamp48V(s): return "get 48V \(s)"
        case let .getHPFOn(a): return "get HPF on \(a)"
        case let .getHPFFrequency(a): return "get HPF freq \(a)"
        case let .getPEQ(a, b, p): return "get PEQ \(a) band \(b) \(p.name)"
        case .raw: return "raw"
        }
    }

    static func peqParamID(band: Int, _ p: PEQParam) -> UInt8 {
        DLive.NRPN.peqFirst + UInt8(max(0, min(3, band)) * 4) + p.rawValue
    }

    /// Encode to bytes (always full status bytes, no running status).
    /// `base` is the zero-based base MIDI channel N (0 = MIDI channel 1).
    public func encode(base: UInt8) -> [UInt8] {
        let N = base & 0x0F
        func nrpn(_ a: ChannelAddress, _ param: UInt8, _ value: UInt8) -> [UInt8] {
            let b = 0xB0 | a.midiChannel(base: N)
            return [b, 0x63, a.chByte, b, 0x62, param & 0x7F, b, 0x06, value & 0x7F]
        }
        func sysex(_ body: [UInt8]) -> [UInt8] { DLive.sysExHeader + body.map { $0 & 0x7F } + [0xF7] }
        func n(_ a: ChannelAddress) -> UInt8 { a.midiChannel(base: N) }
        func getParam(_ a: ChannelAddress, _ id: UInt8) -> [UInt8] {
            sysex([n(a), DLive.SysExFn.get, 0x0B, id, a.chByte])
        }

        switch self {
        case let .mute(a, on):
            let s = 0x90 | n(a)
            return [s, a.chByte, on ? 0x7F : 0x3F, s, a.chByte, 0x00]
        case let .level(a, v):
            return nrpn(a, DLive.NRPN.faderLevel, v)
        case let .mainAssign(a, on):
            return nrpn(a, DLive.NRPN.mainAssign, on ? 0x7F : 0x3F)
        case let .dcaAssign(a, d, on):
            return nrpn(a, DLive.NRPN.dcaMuteGroupAssign, UInt8(max(0, min(23, d))) + (on ? 0x40 : 0x00))
        case let .muteGroupAssign(a, g, on):
            return nrpn(a, DLive.NRPN.dcaMuteGroupAssign, UInt8(max(0, min(7, g))) + (on ? 0x58 : 0x18))
        case let .sendLevel(f, t, v):
            return sysex([n(f), DLive.SysExFn.sendLevel, f.chByte, n(t), t.chByte, v])
        case let .sendAssign(f, t, on):
            return sysex([n(f), DLive.SysExFn.sendAssign, f.chByte, n(t), t.chByte, on ? 0x7F : 0x00])
        case let .setName(a, name):
            return sysex([n(a), DLive.SysExFn.setName, a.chByte] + Self.nameBytes(name))
        case let .setColour(a, c):
            return sysex([n(a), DLive.SysExFn.setColour, a.chByte, c.rawValue])
        case let .preampGain(s, v):
            return [0xE0 | N, s.mp, v & 0x7F]
        case let .preampPad(s, on):
            return sysex([N, DLive.SysExFn.setPad, s.mp, on ? 0x7F : 0x00])
        case let .preamp48V(s, on):
            return sysex([N, DLive.SysExFn.set48V, s.mp, on ? 0x7F : 0x00])
        case let .hpfOn(a, on):
            return nrpn(a, DLive.NRPN.hpfOn, on ? 0x7F : 0x00)
        case let .hpfFrequency(a, v):
            return nrpn(a, DLive.NRPN.hpfFrequency, v)
        case let .peq(a, band, p, v):
            return nrpn(a, Self.peqParamID(band: band, p), v)
        case let .recallScene(scene):
            let s = max(1, min(500, scene)) - 1
            return [0xB0 | N, 0x00, UInt8(s / 128), 0xC0 | N, UInt8(s % 128)]
        case let .recallCue(id):
            let i = max(0, min(1999, id))
            return [0xB0 | N, 0x00, UInt8(i / 128), 0xC0 | N, UInt8(i % 128)]
        case let .ufxKey(k):
            return [0xB0 | N, DLive.CC.ufxGlobalKey, k.rawValue]
        case let .ufxScale(s):
            return [0xB0 | N, DLive.CC.ufxGlobalScale, s.rawValue]
        case let .controlChange(num, v):
            return [0xB0 | N, num & 0x7F, v & 0x7F]

        case let .getName(a):
            return sysex([n(a), DLive.SysExFn.getName, a.chByte])
        case let .getColour(a):
            return sysex([n(a), DLive.SysExFn.getColour, a.chByte])
        case let .getLevel(a):
            return getParam(a, DLive.NRPN.faderLevel)
        case let .getMute(a):
            return sysex([n(a), DLive.SysExFn.get, 0x09, a.chByte])
        case let .getMainAssign(a):
            return getParam(a, DLive.NRPN.mainAssign)
        case let .getSendLevel(f, t):
            return sysex([n(f), DLive.SysExFn.get, 0x0F, DLive.SysExFn.sendLevel, f.chByte, n(t), t.chByte])
        case let .getSendAssign(f, t):
            return sysex([n(f), DLive.SysExFn.get, 0x0F, DLive.SysExFn.sendAssign, f.chByte, n(t), t.chByte])
        case let .getPreampGain(s):
            return sysex([N, DLive.SysExFn.get, 0x0B, DLive.NRPN.preampGain, s.mp])
        case let .getPreampPad(s):
            return sysex([N, DLive.SysExFn.getPad, s.mp])
        case let .getPreamp48V(s):
            return sysex([N, DLive.SysExFn.get48V, s.mp])
        case let .getHPFOn(a):
            return getParam(a, DLive.NRPN.hpfOn)
        case let .getHPFFrequency(a):
            return getParam(a, DLive.NRPN.hpfFrequency)
        case let .getPEQ(a, band, p):
            return getParam(a, Self.peqParamID(band: band, p))

        case let .raw(b):
            return b
        }
    }

    /// "Name = Hex ASCII String". Limited to printable ASCII, 8 characters.
    public static func nameBytes(_ s: String) -> [UInt8] {
        let bytes = s.unicodeScalars.map { $0.isASCII && $0.value >= 0x20 && $0.value < 0x7F ? UInt8($0.value) : UInt8(ascii: "?") }
        return Array(bytes.prefix(8))
    }
}

// MARK: - Incoming events

public enum DLiveEvent: Equatable, Sendable, CustomStringConvertible {
    case mute(ChannelAddress, Bool)
    case level(ChannelAddress, UInt8)
    case mainAssign(ChannelAddress, Bool)
    case dcaAssign(ChannelAddress, dca: Int, assigned: Bool)
    case muteGroupAssign(ChannelAddress, group: Int, assigned: Bool)
    case sendLevel(from: ChannelAddress, to: ChannelAddress, UInt8)
    case sendAssign(from: ChannelAddress, to: ChannelAddress, Bool)
    case name(ChannelAddress, String)
    case colour(ChannelAddress, UInt8)
    case preampGain(PreampSocket, UInt8)
    case preampPad(PreampSocket, Bool)
    case preamp48V(PreampSocket, Bool)
    case hpfOn(ChannelAddress, Bool)
    case hpfFrequency(ChannelAddress, UInt8)
    case peq(ChannelAddress, band: Int, PEQParam, UInt8)
    /// Bank + program change on N. On a MixRack this is scene (bank*128+program+1);
    /// on a Surface it is cue Recall Id (bank*128+program).
    case recall(bank: UInt8, program: UInt8)
    case ufxKey(UInt8)
    case ufxScale(UInt8)
    case controlChange(number: UInt8, value: UInt8)
    case unknown(MIDIMessage)

    public var description: String {
        switch self {
        case let .mute(a, on): return "\(a) mute \(on ? "ON" : "OFF")"
        case let .level(a, v): return "\(a) level \(FaderLaw.label(for: v)) dB"
        case let .mainAssign(a, on): return "\(a) main assign \(on ? "ON" : "OFF")"
        case let .dcaAssign(a, d, on): return "\(a) \(on ? "assigned to" : "unassigned from") DCA \(d + 1)"
        case let .muteGroupAssign(a, g, on): return "\(a) \(on ? "assigned to" : "unassigned from") MG \(g + 1)"
        case let .sendLevel(f, t, v): return "\(f) → \(t) send \(FaderLaw.label(for: v)) dB"
        case let .sendAssign(f, t, on): return "\(f) → \(t) assign \(on ? "ON" : "OFF")"
        case let .name(a, n): return "\(a) name \"\(n)\""
        case let .colour(a, c): return "\(a) colour \(ChannelColour(rawValue: c)?.name ?? String(c))"
        case let .preampGain(s, v): return "\(s) gain \(PreampGainLaw.label(for: v)) dB"
        case let .preampPad(s, on): return "\(s) pad \(on ? "ON" : "OFF")"
        case let .preamp48V(s, on): return "\(s) 48V \(on ? "ON" : "OFF")"
        case let .hpfOn(a, on): return "\(a) HPF \(on ? "ON" : "OFF")"
        case let .hpfFrequency(a, v): return "\(a) HPF freq \(v)"
        case let .peq(a, b, p, v): return "\(a) PEQ band \(b) \(p.name) \(v)"
        case let .recall(bank, program):
            let i = Int(bank) * 128 + Int(program)
            return "recall: scene \(i + 1) (MixRack) / cue id \(i) (Surface)"
        case let .ufxKey(k): return "UFX key \(UFXKey(rawValue: k)?.name ?? String(k))"
        case let .ufxScale(s): return "UFX scale \(UFXScale(rawValue: s)?.name ?? String(s))"
        case let .controlChange(n, v): return String(format: "CC %02X = %02X", n, v)
        case .unknown: return "unrecognised"
        }
    }
}

/// Stateful decoder: tracks NRPN parameter selection and bank per MIDI channel.
/// Feed it messages from `MIDIStreamParser` (which resolves running status).
public struct DLiveDecoder {
    public var base: UInt8 { didSet { base &= 0x0F } }
    private var nrpnMSB = [UInt8?](repeating: nil, count: 16)
    private var nrpnLSB = [UInt8?](repeating: nil, count: 16)
    private var bank = [UInt8](repeating: 0, count: 16)

    public init(base: UInt8) { self.base = base & 0x0F }

    private func offset(of midiChannel: UInt8) -> UInt8? {
        let o = (Int(midiChannel) - Int(base) + 16) % 16
        return o <= 4 ? UInt8(o) : nil
    }

    private func address(_ midiChannel: UInt8, _ ch: UInt8) -> ChannelAddress? {
        guard let off = offset(of: midiChannel) else { return nil }
        return ChannelAddress.from(offset: off, ch: ch)
    }

    public mutating func decode(_ msg: MIDIMessage) -> DLiveEvent? {
        switch msg {
        case let .channel(status, d1, d2):
            let ch = status & 0x0F
            switch status & 0xF0 {
            case 0x90:
                // "Velocity 00 and NOTE OFF messages are ignored."
                guard let d2, d2 != 0 else { return nil }
                guard let a = address(ch, d1) else { return .unknown(msg) }
                return .mute(a, d2 >= 0x40)
            case 0x80:
                return nil
            case 0xB0:
                guard let d2 else { return nil }
                switch d1 {
                case 0x63: nrpnMSB[Int(ch)] = d2; return nil
                case 0x62: nrpnLSB[Int(ch)] = d2; return nil
                case 0x06:
                    guard let msb = nrpnMSB[Int(ch)], let lsb = nrpnLSB[Int(ch)] else { return .unknown(msg) }
                    return decodeNRPN(ch, msb, lsb, d2) ?? .unknown(msg)
                case DLive.CC.bankSelect where ch == base:
                    bank[Int(ch)] = d2; return nil
                case DLive.CC.ufxGlobalKey where ch == base:
                    return .ufxKey(d2)
                case DLive.CC.ufxGlobalScale where ch == base:
                    return .ufxScale(d2)
                default:
                    return ch == base ? .controlChange(number: d1, value: d2) : .unknown(msg)
                }
            case 0xC0:
                guard ch == base else { return .unknown(msg) }
                return .recall(bank: bank[Int(ch)], program: d1)
            case 0xE0:
                // "Set Socket Preamp Gain: EN, MP, GV"
                guard ch == base, let d2 else { return .unknown(msg) }
                return .preampGain(PreampSocket(mp: d1), d2)
            default:
                return .unknown(msg)
            }
        case let .sysEx(bytes):
            return decodeSysEx(bytes) ?? .unknown(msg)
        case .system:
            return nil
        }
    }

    private func decodeNRPN(_ midiChannel: UInt8, _ chByte: UInt8, _ param: UInt8, _ value: UInt8) -> DLiveEvent? {
        guard let a = address(midiChannel, chByte) else { return nil }
        switch param {
        case DLive.NRPN.faderLevel:
            return .level(a, value)
        case DLive.NRPN.mainAssign:
            return .mainAssign(a, value >= 0x40)
        case DLive.NRPN.hpfOn:
            return .hpfOn(a, value >= 0x40)
        case DLive.NRPN.hpfFrequency:
            return .hpfFrequency(a, value)
        case 0x1A...0x29:
            let i = Int(param - DLive.NRPN.peqFirst)
            return .peq(a, band: i / 4, PEQParam(rawValue: UInt8(i % 4))!, value)
        case DLive.NRPN.dcaMuteGroupAssign:
            switch value {
            case 0x00...0x17: return .dcaAssign(a, dca: Int(value), assigned: false)
            case 0x18...0x1F: return .muteGroupAssign(a, group: Int(value - 0x18), assigned: false)
            case 0x40...0x57: return .dcaAssign(a, dca: Int(value - 0x40), assigned: true)
            case 0x58...0x5F: return .muteGroupAssign(a, group: Int(value - 0x58), assigned: true)
            default: return nil
            }
        default:
            return nil
        }
    }

    private func decodeSysEx(_ b: [UInt8]) -> DLiveEvent? {
        let h = DLive.sysExHeader
        guard b.count >= h.count + 3, Array(b.prefix(h.count)) == h, b.last == 0xF7 else { return nil }
        let body = Array(b[h.count..<(b.count - 1)])
        guard body.count >= 3 else { return nil }
        let midi = body[0] & 0x0F
        let fn = body[1]
        switch fn {
        case DLive.SysExFn.nameReply, DLive.SysExFn.setName:
            guard let a = address(midi, body[2]) else { return nil }
            let nameBytes = body.dropFirst(3).filter { $0 != 0 }
            return .name(a, String(decoding: nameBytes, as: UTF8.self))
        case DLive.SysExFn.colourReply where body.count == 4,
             DLive.SysExFn.setColour where body.count == 4:
            guard let a = address(midi, body[2]) else { return nil }
            return .colour(a, body[3])
        case DLive.SysExFn.padReply where body.count == 4 && midi == base,
             DLive.SysExFn.setPad where body.count == 4 && midi == base:
            return .preampPad(PreampSocket(mp: body[2]), body[3] >= 0x40)
        case DLive.SysExFn.phantomReply where body.count == 4 && midi == base,
             DLive.SysExFn.set48V where body.count == 4 && midi == base:
            return .preamp48V(PreampSocket(mp: body[2]), body[3] >= 0x40)
        case DLive.SysExFn.sendLevel where body.count == 6,
             DLive.SysExFn.sendAssign where body.count == 6:
            guard let from = address(midi, body[2]), let to = address(body[3] & 0x0F, body[4]) else { return nil }
            return fn == DLive.SysExFn.sendLevel
                ? .sendLevel(from: from, to: to, body[5])
                : .sendAssign(from: from, to: to, body[5] >= 0x40)
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

    /// Parses "B0 63 01", "b0,63,01", "0xB0 0x63", "B06301". Returns nil on any invalid token.
    public static func parse(_ s: String) -> [UInt8]? {
        let cleaned = s.replacingOccurrences(of: "0x", with: " ", options: .caseInsensitive)
        let tokens = cleaned.split(whereSeparator: { " ,;\t\n".contains($0) })
        var out: [UInt8] = []
        for t in tokens {
            if t.count == 1 {
                guard let v = UInt8(t, radix: 16) else { return nil }
                out.append(v)
                continue
            }
            guard t.count % 2 == 0 else { return nil }
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

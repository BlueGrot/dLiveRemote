import Foundation

/// Conversion between MIDI 1.0 byte messages and Universal MIDI Packets (MIDI 1.0 protocol),
/// as used by CoreMIDI's MIDIEventList APIs. Pure Swift, no CoreMIDI dependency.
public enum UMP {
    /// Number of 32-bit words in a UMP, from the message type in the first word.
    public static func wordCount(_ firstWord: UInt32) -> Int {
        switch firstWord >> 28 {
        case 0x0, 0x1, 0x2, 0x6, 0x7: return 1
        case 0x3, 0x4, 0x8, 0x9, 0xA: return 2
        case 0xB, 0xC: return 3
        default: return 4
        }
    }

    /// Encode one MIDI 1.0 message as UMP words.
    public static func words(for msg: MIDIMessage, group: UInt8 = 0) -> [UInt32] {
        let g = UInt32(group & 0x0F) << 24
        switch msg {
        case let .channel(status, d1, d2):
            return [0x2000_0000 | g | UInt32(status) << 16 | UInt32(d1 & 0x7F) << 8 | UInt32((d2 ?? 0) & 0x7F)]
        case let .system(bytes):
            guard let s = bytes.first else { return [] }
            let b1 = bytes.count > 1 ? UInt32(bytes[1] & 0x7F) : 0
            let b2 = bytes.count > 2 ? UInt32(bytes[2] & 0x7F) : 0
            return [0x1000_0000 | g | UInt32(s) << 16 | b1 << 8 | b2]
        case let .sysEx(bytes):
            // Payload without F0 / F7, split into 6-byte SysEx7 packets.
            var payload = bytes
            if payload.first == 0xF0 { payload.removeFirst() }
            if payload.last == 0xF7 { payload.removeLast() }
            var out: [UInt32] = []
            let chunks = stride(from: 0, to: max(payload.count, 1), by: 6).map {
                Array(payload[$0..<min($0 + 6, payload.count)])
            }
            for (i, chunk) in chunks.enumerated() {
                let status: UInt32
                if chunks.count == 1 { status = 0 }          // complete in one packet
                else if i == 0 { status = 1 }                // start
                else if i == chunks.count - 1 { status = 3 } // end
                else { status = 2 }                          // continue
                var b = chunk.map { UInt32($0 & 0x7F) }
                while b.count < 6 { b.append(0) }
                out.append(0x3000_0000 | g | status << 20 | UInt32(chunk.count) << 16 | b[0] << 8 | b[1])
                out.append(b[2] << 24 | b[3] << 16 | b[4] << 8 | b[5])
            }
            return out
        }
    }

    /// Stateful decoder from UMP words back to MIDI 1.0 byte messages.
    /// Ignores MIDI 2.0 channel voice, utility and other non-MIDI-1.0 packets.
    public struct Decoder {
        private var sysEx: [UInt8]? = nil
        public var maxSysExLength = 8192

        public init() {}

        public mutating func feed<C: Collection>(_ words: C) -> [[UInt8]] where C.Element == UInt32, C.Index == Int {
            var out: [[UInt8]] = []
            var i = words.startIndex
            while i < words.endIndex {
                let w0 = words[i]
                let n = UMP.wordCount(w0)
                guard i + n <= words.endIndex else { break }
                switch w0 >> 28 {
                case 0x1:
                    let s = UInt8((w0 >> 16) & 0xFF)
                    let b1 = UInt8((w0 >> 8) & 0x7F), b2 = UInt8(w0 & 0x7F)
                    switch s {
                    case 0xF1, 0xF3: out.append([s, b1])
                    case 0xF2: out.append([s, b1, b2])
                    default: out.append([s])
                    }
                case 0x2:
                    let s = UInt8((w0 >> 16) & 0xFF)
                    let b1 = UInt8((w0 >> 8) & 0x7F), b2 = UInt8(w0 & 0x7F)
                    switch s & 0xF0 {
                    case 0xC0, 0xD0: out.append([s, b1])
                    default: out.append([s, b1, b2])
                    }
                case 0x3:
                    let w1 = words[i + 1]
                    let status = (w0 >> 20) & 0xF
                    let count = Int(min(6, (w0 >> 16) & 0xF))
                    let all: [UInt8] = [UInt8((w0 >> 8) & 0x7F), UInt8(w0 & 0x7F),
                                        UInt8((w1 >> 24) & 0x7F), UInt8((w1 >> 16) & 0x7F),
                                        UInt8((w1 >> 8) & 0x7F), UInt8(w1 & 0x7F)]
                    let data = Array(all.prefix(count))
                    switch status {
                    case 0: out.append([0xF0] + data + [0xF7]); sysEx = nil
                    case 1: sysEx = data
                    case 2: sysEx? += data
                    case 3:
                        if let s = sysEx { out.append([0xF0] + s + data + [0xF7]) }
                        sysEx = nil
                    default: break
                    }
                    if let s = sysEx, s.count > maxSysExLength { sysEx = nil }
                default:
                    break
                }
                i += n
            }
            return out
        }
    }
}

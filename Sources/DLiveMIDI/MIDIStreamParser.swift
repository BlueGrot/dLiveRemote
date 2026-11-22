import Foundation

/// A complete MIDI message extracted from a byte stream.
public enum MIDIMessage: Equatable, Sendable {
    /// Channel voice message. `status` includes the channel nibble.
    case channel(status: UInt8, data1: UInt8, data2: UInt8?)
    /// Complete System Exclusive message including the leading 0xF0 and trailing 0xF7.
    case sysEx([UInt8])
    /// Any other system message (system common / realtime).
    case system([UInt8])

    public var bytes: [UInt8] {
        switch self {
        case let .channel(status, d1, d2):
            if let d2 { return [status, d1, d2] }
            return [status, d1]
        case let .sysEx(b), let .system(b):
            return b
        }
    }

    public var channelNibble: UInt8? {
        if case let .channel(status, _, _) = self { return status & 0x0F }
        return nil
    }

    public var kindNibble: UInt8? {
        if case let .channel(status, _, _) = self { return status & 0xF0 }
        return nil
    }
}

/// Incremental parser that turns an arbitrary chunked TCP byte stream into MIDI messages.
/// Supports running status, interleaved realtime bytes and SysEx of any length.
public struct MIDIStreamParser {
    private var status: UInt8? = nil      // current running status (channel voice) or system common status
    private var pending: [UInt8] = []     // data bytes collected for the current message
    private var sysEx: [UInt8]? = nil     // non-nil while inside a SysEx
    public var maxSysExLength = 4096

    public init() {}

    public mutating func feed<S: Sequence>(_ bytes: S) -> [MIDIMessage] where S.Element == UInt8 {
        var out: [MIDIMessage] = []
        for b in bytes { feed(byte: b, into: &out) }
        return out
    }

    private static func dataLength(for status: UInt8) -> Int {
        switch status & 0xF0 {
        case 0x80, 0x90, 0xA0, 0xB0, 0xE0: return 2
        case 0xC0, 0xD0: return 1
        default:
            switch status {
            case 0xF1, 0xF3: return 1
            case 0xF2: return 2
            default: return 0
            }
        }
    }

    private mutating func feed(byte b: UInt8, into out: inout [MIDIMessage]) {
        // Realtime bytes may appear anywhere, even inside SysEx, and don't affect state.
        if b >= 0xF8 {
            out.append(.system([b]))
            return
        }

        if b == 0xF0 {
            sysEx = [0xF0]
            status = nil
            pending.removeAll()
            return
        }

        if b == 0xF7 {
            if var s = sysEx {
                s.append(0xF7)
                out.append(.sysEx(s))
            }
            sysEx = nil
            return
        }

        if sysEx != nil {
            if b & 0x80 != 0 {
                // A status byte aborts an unterminated SysEx; process it as normal.
                sysEx = nil
            } else {
                sysEx!.append(b)
                if sysEx!.count > maxSysExLength { sysEx = nil }
                return
            }
        }

        if b & 0x80 != 0 {
            // New status byte.
            pending.removeAll()
            if b >= 0xF0 {
                // System common: cancels running status.
                let n = Self.dataLength(for: b)
                if n == 0 {
                    out.append(.system([b]))
                    status = nil
                } else {
                    status = b
                }
            } else {
                status = b
            }
            return
        }

        // Data byte.
        guard let s = status else { return } // stray data, ignore
        pending.append(b)
        let need = Self.dataLength(for: s)
        if pending.count == need {
            if s >= 0xF0 {
                out.append(.system([s] + pending))
                status = nil
            } else {
                out.append(.channel(status: s, data1: pending[0], data2: need == 2 ? pending[1] : nil))
            }
            pending.removeAll()
        }
    }
}

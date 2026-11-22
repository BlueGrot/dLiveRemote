import Foundation

/// Minimal OSC 1.0 message encoder (int32, float32, string arguments).
public struct OSCMessage: Equatable, Sendable {
    public enum Argument: Equatable, Sendable {
        case int(Int32)
        case float(Float)
        case string(String)
    }

    public var address: String
    public var arguments: [Argument]

    public init(_ address: String, _ arguments: [Argument] = []) {
        self.address = address
        self.arguments = arguments
    }

    public func encoded() -> [UInt8] {
        var out = Self.paddedString(address)
        var tags = ","
        for a in arguments {
            switch a {
            case .int: tags += "i"
            case .float: tags += "f"
            case .string: tags += "s"
            }
        }
        out += Self.paddedString(tags)
        for a in arguments {
            switch a {
            case let .int(v):
                out += Self.bigEndian(UInt32(bitPattern: v))
            case let .float(v):
                out += Self.bigEndian(v.bitPattern)
            case let .string(s):
                out += Self.paddedString(s)
            }
        }
        return out
    }

    static func paddedString(_ s: String) -> [UInt8] {
        var b = Array(s.utf8)
        b.append(0)
        while b.count % 4 != 0 { b.append(0) }
        return b
    }

    static func bigEndian(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }
}

import XCTest
@testable import DLiveMIDI

final class UMPTests: XCTestCase {
    func roundTrip(_ msgs: [MIDIMessage]) -> [[UInt8]] {
        var d = UMP.Decoder()
        return d.feed(msgs.flatMap { UMP.words(for: $0) })
    }

    func testChannelVoice() {
        XCTAssertEqual(UMP.words(for: .channel(status: 0x9B, data1: 0x00, data2: 0x7F)), [0x209B_007F])
        XCTAssertEqual(UMP.words(for: .channel(status: 0xCB, data1: 0x05, data2: nil)), [0x20CB_0500])
        XCTAssertEqual(roundTrip([.channel(status: 0xBB, data1: 0x63, data2: 0x01),
                                  .channel(status: 0xCB, data1: 0x05, data2: nil),
                                  .channel(status: 0xEB, data1: 0x02, data2: 0x40)]),
                       [[0xBB, 0x63, 0x01], [0xCB, 0x05], [0xEB, 0x02, 0x40]])
    }

    func testSysExShortAndLong() {
        let name = DLiveCommand.setName(ChannelAddress(.input, 0), "LeadVox1").encode(base: 0x0B)
        let short: [UInt8] = [0xF0, 0x01, 0x02, 0xF7]
        let empty: [UInt8] = [0xF0, 0xF7]
        XCTAssertEqual(UMP.words(for: .sysEx(short)).count, 2)
        XCTAssertEqual(roundTrip([.sysEx(name), .sysEx(short), .sysEx(empty)]), [name, short, empty])
        // exactly 6 and 12 payload bytes
        let six: [UInt8] = [0xF0] + Array(1...6) + [0xF7]
        let twelve: [UInt8] = [0xF0] + Array(1...12) + [0xF7]
        XCTAssertEqual(roundTrip([.sysEx(six), .sysEx(twelve)]), [six, twelve])
    }

    func testSystemAndSkipsOtherTypes() {
        var d = UMP.Decoder()
        // MIDI 2.0 note on (type 4, 2 words) must be skipped without desyncing
        let words: [UInt32] = [0x4090_3C00, 0xFFFF_0000] + UMP.words(for: .system([0xF8]))
        XCTAssertEqual(d.feed(words), [[0xF8]])
    }

    func testWholeStreamFromParser() {
        var p = MIDIStreamParser()
        let stream: [UInt8] = [0x9B, 0x00, 0x7F, 0x01, 0x7F] + DLiveCommand.getName(ChannelAddress(.dca, 0)).encode(base: 0x0B)
        let msgs = p.feed(stream)
        XCTAssertEqual(roundTrip(msgs), msgs.map(\.bytes))
    }
}

import XCTest
@testable import DLiveMIDI

final class EncodeTests: XCTestCase {
    // Base MIDI channel 12 -> N = 0x0B
    let N: UInt8 = 11

    func testMuteInput1() {
        let a = ChannelAddress(.input, 0)
        XCTAssertEqual(DLiveCommand.mute(a, true).encode(base: N), [0x9B, 0x00, 0x7F, 0x9B, 0x00, 0x00])
        XCTAssertEqual(DLiveCommand.mute(a, false).encode(base: N), [0x9B, 0x00, 0x3F, 0x9B, 0x00, 0x00])
    }

    func testFaderLevelStereoAux2() {
        let a = ChannelAddress(.stereoAux, 1) // N+2, CH 0x41
        XCTAssertEqual(DLiveCommand.level(a, 0x6B).encode(base: N),
                       [0xBD, 0x63, 0x41, 0xBD, 0x62, 0x17, 0xBD, 0x06, 0x6B])
    }

    func testDCAAndMuteGroupAddressing() {
        XCTAssertEqual(ChannelAddress(.dca, 0).chByte, 0x36)
        XCTAssertEqual(ChannelAddress(.dca, 23).chByte, 0x4D)
        XCTAssertEqual(ChannelAddress(.muteGroup, 7).chByte, 0x55)
        XCTAssertEqual(ChannelAddress(.main, 0).midiChannel(base: N), 0x0F)
    }

    func testDCAAssign() {
        let a = ChannelAddress(.input, 4)
        XCTAssertEqual(DLiveCommand.dcaAssign(a, dca: 2, assigned: true).encode(base: N),
                       [0xBB, 0x63, 0x04, 0xBB, 0x62, 0x40, 0xBB, 0x06, 0x42])
        XCTAssertEqual(DLiveCommand.muteGroupAssign(a, group: 0, assigned: false).encode(base: N).last, 0x18)
    }

    func testName() {
        let a = ChannelAddress(.input, 2)
        XCTAssertEqual(DLiveCommand.setName(a, "Vox").encode(base: N),
                       DLive.sysExHeader + [0x0B, 0x03, 0x02, 0x56, 0x6F, 0x78, 0xF7])
        XCTAssertEqual(DLiveCommand.nameBytes("ThisIsTooLong").count, 8)
    }

    func testSceneRecall() {
        XCTAssertEqual(DLiveCommand.recallScene(1).encode(base: N), [0xBB, 0x00, 0x00, 0xCB, 0x00])
        XCTAssertEqual(DLiveCommand.recallScene(130).encode(base: N), [0xBB, 0x00, 0x01, 0xCB, 0x01])
    }

    func testSendLevel() {
        let from = ChannelAddress(.input, 0)
        let to = ChannelAddress(.monoAux, 3)
        XCTAssertEqual(DLiveCommand.sendLevel(from: from, to: to, 0x6B).encode(base: N),
                       DLive.sysExHeader + [0x0B, 0x0D, 0x00, 0x0D, 0x03, 0x6B, 0xF7])
    }

    func testFaderLaw() {
        XCTAssertEqual(FaderLaw.value(fromDB: 0), 0x6B)
        XCTAssertEqual(FaderLaw.value(fromDB: 10), 0x7F)
        XCTAssertEqual(FaderLaw.value(fromDB: -100), 0)
        XCTAssertNil(FaderLaw.dB(from: 0))
        XCTAssertEqual(FaderLaw.dB(from: 0x6B)!, 0, accuracy: 0.5)
    }
}

final class ParseTests: XCTestCase {
    func testChunkedNRPNWithRunningStatus() {
        var p = MIDIStreamParser()
        var d = DLiveDecoder(base: 11)
        // Running status: BB 63 00 62 17 06 6B, delivered in awkward chunks.
        var events: [DLiveEvent] = []
        for chunk in [[0xBB, 0x63], [0x00, 0x62, 0x17], [0x06], [0x6B]] as [[UInt8]] {
            for m in p.feed(chunk) { if let e = d.decode(m) { events.append(e) } }
        }
        XCTAssertEqual(events, [.level(ChannelAddress(.input, 0), 0x6B)])
    }

    func testMuteRoundTrip() {
        var p = MIDIStreamParser()
        var d = DLiveDecoder(base: 11)
        let bytes = DLiveCommand.mute(ChannelAddress(.dca, 3), true).encode(base: 11)
        let events = p.feed(bytes).compactMap { d.decode($0) }
        XCTAssertEqual(events, [.mute(ChannelAddress(.dca, 3), true)])
    }

    func testNameReply() {
        var p = MIDIStreamParser()
        var d = DLiveDecoder(base: 0)
        let bytes = DLive.sysExHeader + [0x01, 0x02, 0x40, 0x44, 0x72, 0x75, 0x6D, 0x73, 0xF7]
        let events = p.feed(bytes).compactMap { d.decode($0) }
        XCTAssertEqual(events, [.name(ChannelAddress(.stereoGroup, 0), "Drums")])
    }

    func testSceneRecallDecode() {
        var p = MIDIStreamParser()
        var d = DLiveDecoder(base: 11)
        let events = p.feed(DLiveCommand.recallScene(300).encode(base: 11)).compactMap { d.decode($0) }
        XCTAssertEqual(events, [.sceneRecalled(300)])
    }

    func testRealtimeInsideSysEx() {
        var p = MIDIStreamParser()
        let msgs = p.feed([0xF0, 0x00, 0xF8, 0x01, 0xF7])
        XCTAssertEqual(msgs, [.system([0xF8]), .sysEx([0xF0, 0x00, 0x01, 0xF7])])
    }

    func testHexParse() {
        XCTAssertEqual(Hex.parse("B0 63 0x01,62"), [0xB0, 0x63, 0x01, 0x62])
        XCTAssertEqual(Hex.parse("b06301"), [0xB0, 0x63, 0x01])
        XCTAssertNil(Hex.parse("zz"))
    }
}

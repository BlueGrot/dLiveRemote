import XCTest
@testable import DLiveMIDI

final class BridgeRouterTests: XCTestCase {
    let N: UInt8 = 0x0B

    func run(_ bytes: [UInt8], _ s: BridgeSettings = BridgeSettings()) -> [BridgeOutput] {
        var p = MIDIStreamParser()
        var r = BridgeRouter(settings: s, base: N)
        return p.feed(bytes).flatMap { r.process($0) }
    }

    func mainBytes(_ out: [BridgeOutput]) -> [UInt8] {
        out.flatMap { o -> [UInt8] in
            if case let .midi(.main, m) = o { return m.bytes }
            return []
        }
    }

    func testForwardsEverythingByDefault() {
        let stream: [UInt8] = DLiveCommand.mute(ChannelAddress(.input, 0), true).encode(base: N)
            + DLiveCommand.level(ChannelAddress(.input, 1), 0x6B).encode(base: N)
            + DLiveCommand.recallScene(5).encode(base: N)
            + [0xB1, 0x00, 0x40] // MIDI strip fader
            + DLiveCommand.setName(ChannelAddress(.input, 0), "Kick").encode(base: N)
        XCTAssertEqual(mainBytes(run(stream)), stream)
    }

    func testCategoryFilterKeepsNRPNTogether() {
        var s = BridgeSettings()
        s.forwardedCategories = [.mutes, .recalls]
        let fader = DLiveCommand.level(ChannelAddress(.input, 1), 0x6B).encode(base: N)
        let assign = DLiveCommand.mainAssign(ChannelAddress(.input, 1), true).encode(base: N)
        let mute = DLiveCommand.mute(ChannelAddress(.input, 0), true).encode(base: N)
        let scene = DLiveCommand.recallScene(130).encode(base: N)
        XCTAssertEqual(mainBytes(run(fader + assign + mute + scene, s)), mute + scene)

        s.forwardedCategories = [.faders]
        XCTAssertEqual(mainBytes(run(fader + assign + mute, s)), fader)
        s.forwardedCategories = [.processing]
        XCTAssertEqual(mainBytes(run(fader + assign + mute, s)), assign)
    }

    func testSplitPorts() {
        var s = BridgeSettings()
        s.splitPorts = true
        let out = run(DLiveCommand.recallScene(2).encode(base: N) + [0x91, 0x03, 0x7F], s)
        XCTAssertTrue(out.contains(.midi(.category(.recalls), .channel(status: 0xCB, data1: 0x01, data2: nil))))
        XCTAssertTrue(out.contains(.midi(.category(.recalls), .channel(status: 0xBB, data1: 0x00, data2: 0x00))))
        XCTAssertTrue(out.contains(.midi(.category(.midiStrips), .channel(status: 0x91, data1: 0x03, data2: 0x7F))))
    }

    func testChannelRemap() {
        var s = BridgeSettings()
        s.channelMap[1] = 0   // MIDI ch 2 → ch 1
        s.channelMap[0x0B] = 0x0F
        XCTAssertEqual(mainBytes(run([0xB1, 0x05, 0x10, 0x9B, 0x00, 0x7F], s)), [0xB0, 0x05, 0x10, 0x9F, 0x00, 0x7F])
    }

    func testMSCOnRecall() {
        var s = BridgeSettings()
        s.msc.enabled = true
        let out = run(DLiveCommand.recallScene(12).encode(base: N), s)
        XCTAssertTrue(out.contains(.midi(.showControl, .sysEx([0xF0, 0x7F, 0x7F, 0x02, 0x7F, 0x01, 0x31, 0x32, 0xF7]))))
        s.target = .surface
        s.msc.cueList = "2"
        let out2 = run(DLiveCommand.recallCue(7).encode(base: N), s)
        XCTAssertTrue(out2.contains(.midi(.showControl, .sysEx([0xF0, 0x7F, 0x7F, 0x02, 0x7F, 0x01, 0x37, 0x00, 0x32, 0xF7]))))
    }

    func testOSC() {
        var s = BridgeSettings()
        s.osc.enabled = true
        s.osc.recallAddress = "/cue/{n}/start"
        let out = run(DLiveCommand.recallScene(3).encode(base: N)
                      + DLiveCommand.mute(ChannelAddress(.dca, 1), true).encode(base: N), s)
        XCTAssertTrue(out.contains(.osc(OSCMessage("/cue/3/start"))))
        XCTAssertTrue(out.contains(.osc(OSCMessage("/dlive/mute/dca/2", [.int(1)]))))
        s.osc.recallAddress = "/dlive/scene"
        XCTAssertTrue(run(DLiveCommand.recallScene(3).encode(base: N), s).contains(.osc(OSCMessage("/dlive/scene", [.int(3)]))))
    }

    func testOSCEncoding() {
        XCTAssertEqual(OSCMessage("/a", [.int(1)]).encoded(),
                       [0x2F, 0x61, 0, 0, 0x2C, 0x69, 0, 0, 0, 0, 0, 1])
        var expected: [UInt8] = Array("/abc".utf8)
        expected += [0, 0, 0, 0]
        expected += Array(",fs".utf8)
        expected += [0, 0x3F, 0x80, 0, 0]
        expected += Array("hi".utf8)
        expected += [0, 0]
        XCTAssertEqual(OSCMessage("/abc", [.float(1.0), .string("hi")]).encoded(), expected)
    }

    func testMackie() {
        var s = BridgeSettings()
        s.mackie.enabled = true
        let out = run([0xB1, 0x09, 0x7F,        // strip 10 fader full
                       0x91, 0x01, 0x7F,        // strip 2 mute press
                       0x91, 0x41, 0x00,        // strip 2 PAFL release
                       0xB2, 0x22, 0x40, 0xB2, 0x22, 0x43, 0xB2, 0x22, 0x41], s)
        XCTAssertTrue(out.contains(.midi(.mackie(1), .channel(status: 0xE1, data1: 0x7F, data2: 0x7F))))
        XCTAssertTrue(out.contains(.midi(.mackie(0), .channel(status: 0x90, data1: 0x11, data2: 0x7F))))
        XCTAssertTrue(out.contains(.midi(.mackie(0), .channel(status: 0x90, data1: 0x09, data2: 0x00))))
        XCTAssertTrue(out.contains(.midi(.mackie(0), .channel(status: 0xB0, data1: 0x12, data2: 0x03))))
        XCTAssertTrue(out.contains(.midi(.mackie(0), .channel(status: 0xB0, data1: 0x12, data2: 0x42))))
    }
}

import XCTest
@testable import DLiveMIDI

/// Expected bytes are taken from "dLive MIDI Over TCP/IP Protocol – Firmware V2.0".
final class EncodeTests: XCTestCase {
    // Base MIDI channel 12 -> N = 0x0B (the spec's own examples use channel 12)
    let N: UInt8 = 0x0B
    let H = DLive.sysExHeader

    func testPorts() {
        XCTAssertEqual(DLive.Target.mixRack.port(tls: false), 51325)
        XCTAssertEqual(DLive.Target.mixRack.port(tls: true), 51327)
        XCTAssertEqual(DLive.Target.surface.port(tls: false), 51328)
        XCTAssertEqual(DLive.Target.surface.port(tls: true), 51329)
    }

    func testAuthMessage() {
        XCTAssertEqual(DLive.authMessage(profile: 0x03, password: "abc"), [0x03, 0x61, 0x62, 0x63])
        XCTAssertEqual(DLive.authOK, [0x41, 0x75, 0x74, 0x68, 0x4F, 0x4B])
    }

    func testMute() {
        let a = ChannelAddress(.input, 0)
        XCTAssertEqual(DLiveCommand.mute(a, true).encode(base: N), [0x9B, 0x00, 0x7F, 0x9B, 0x00, 0x00])
        XCTAssertEqual(DLiveCommand.mute(a, false).encode(base: N), [0x9B, 0x00, 0x3F, 0x9B, 0x00, 0x00])
    }

    func testFaderLevel() {
        let a = ChannelAddress(.stereoAux, 1) // N+2, CH 41
        XCTAssertEqual(DLiveCommand.level(a, 0x6B).encode(base: N),
                       [0xBD, 0x63, 0x41, 0xBD, 0x62, 0x17, 0xBD, 0x06, 0x6B])
    }

    func testChannelSelectionTable() {
        XCTAssertEqual(ChannelAddress(.input, 127).chByte, 0x7F)
        XCTAssertEqual(ChannelAddress(.monoGroup, 61).chByte, 0x3D)
        XCTAssertEqual(ChannelAddress(.stereoGroup, 30).chByte, 0x5E)
        XCTAssertEqual(ChannelAddress(.stereoFXSend, 0).chByte, 0x10)
        XCTAssertEqual(ChannelAddress(.fxReturn, 15).chByte, 0x2F)
        XCTAssertEqual(ChannelAddress(.main, 5).chByte, 0x35)
        XCTAssertEqual(ChannelAddress(.dca, 0).chByte, 0x36)
        XCTAssertEqual(ChannelAddress(.dca, 23).chByte, 0x4D)
        XCTAssertEqual(ChannelAddress(.muteGroup, 7).chByte, 0x55)
        XCTAssertEqual(ChannelAddress(.stereoUFXSend, 7).chByte, 0x5D)
        XCTAssertEqual(ChannelAddress(.stereoUFXReturn, 7).chByte, 0x65)
        XCTAssertEqual(ChannelAddress(.main, 0).midiChannel(base: N), 0x0F)
        for kind in ChannelKind.allCases {
            for i in 0..<kind.count {
                let a = ChannelAddress(kind, i)
                XCTAssertEqual(ChannelAddress.from(offset: kind.midiOffset, ch: a.chByte), a)
            }
        }
    }

    func testAssignments() {
        let a = ChannelAddress(.input, 4)
        XCTAssertEqual(DLiveCommand.mainAssign(a, true).encode(base: N),
                       [0xBB, 0x63, 0x04, 0xBB, 0x62, 0x18, 0xBB, 0x06, 0x7F])
        XCTAssertEqual(DLiveCommand.mainAssign(a, false).encode(base: N).last, 0x3F)
        XCTAssertEqual(DLiveCommand.dcaAssign(a, dca: 2, assigned: true).encode(base: N),
                       [0xBB, 0x63, 0x04, 0xBB, 0x62, 0x40, 0xBB, 0x06, 0x42])
        XCTAssertEqual(DLiveCommand.dcaAssign(a, dca: 23, assigned: false).encode(base: N).last, 0x17)
        XCTAssertEqual(DLiveCommand.muteGroupAssign(a, group: 0, assigned: true).encode(base: N).last, 0x58)
        XCTAssertEqual(DLiveCommand.muteGroupAssign(a, group: 7, assigned: false).encode(base: N).last, 0x1F)
    }

    func testNameAndColour() {
        let a = ChannelAddress(.input, 2)
        XCTAssertEqual(DLiveCommand.setName(a, "Vox").encode(base: N), H + [0x0B, 0x03, 0x02, 0x56, 0x6F, 0x78, 0xF7])
        XCTAssertEqual(DLiveCommand.getName(a).encode(base: N), H + [0x0B, 0x01, 0x02, 0xF7])
        XCTAssertEqual(DLiveCommand.setColour(a, .blue).encode(base: N), H + [0x0B, 0x06, 0x02, 0x04, 0xF7])
        XCTAssertEqual(DLiveCommand.getColour(a).encode(base: N), H + [0x0B, 0x04, 0x02, 0xF7])
        XCTAssertEqual(DLiveCommand.nameBytes("ThisIsTooLong").count, 8)
    }

    func testGets() {
        let a = ChannelAddress(.input, 0)
        XCTAssertEqual(DLiveCommand.getMute(a).encode(base: N), H + [0x0B, 0x05, 0x09, 0x00, 0xF7])
        XCTAssertEqual(DLiveCommand.getLevel(a).encode(base: N), H + [0x0B, 0x05, 0x0B, 0x17, 0x00, 0xF7])
        XCTAssertEqual(DLiveCommand.getMainAssign(a).encode(base: N), H + [0x0B, 0x05, 0x0B, 0x18, 0x00, 0xF7])
        XCTAssertEqual(DLiveCommand.getHPFOn(a).encode(base: N), H + [0x0B, 0x05, 0x0B, 0x31, 0x00, 0xF7])
        XCTAssertEqual(DLiveCommand.getHPFFrequency(a).encode(base: N), H + [0x0B, 0x05, 0x0B, 0x30, 0x00, 0xF7])
        XCTAssertEqual(DLiveCommand.getPEQ(a, band: 3, .gain).encode(base: N), H + [0x0B, 0x05, 0x0B, 0x29, 0x00, 0xF7])
    }

    func testSends() {
        let from = ChannelAddress(.input, 0)
        let to = ChannelAddress(.monoAux, 3) // N+2 = 0D, CH 03
        XCTAssertEqual(DLiveCommand.sendLevel(from: from, to: to, 0x6B).encode(base: N),
                       H + [0x0B, 0x0D, 0x00, 0x0D, 0x03, 0x6B, 0xF7])
        XCTAssertEqual(DLiveCommand.getSendLevel(from: from, to: to).encode(base: N),
                       H + [0x0B, 0x05, 0x0F, 0x0D, 0x00, 0x0D, 0x03, 0xF7])
        XCTAssertEqual(DLiveCommand.sendAssign(from: from, to: to, true).encode(base: N),
                       H + [0x0B, 0x0E, 0x00, 0x0D, 0x03, 0x7F, 0xF7])
        XCTAssertEqual(DLiveCommand.getSendAssign(from: from, to: to).encode(base: N),
                       H + [0x0B, 0x05, 0x0F, 0x0E, 0x00, 0x0D, 0x03, 0xF7])
    }

    func testPreamp() {
        let s = PreampSocket(mp: 0x05)
        XCTAssertEqual(DLiveCommand.preampGain(s, 0x40).encode(base: N), [0xEB, 0x05, 0x40])
        XCTAssertEqual(DLiveCommand.getPreampGain(s).encode(base: N), H + [0x0B, 0x05, 0x0B, 0x19, 0x05, 0xF7])
        XCTAssertEqual(DLiveCommand.preampPad(s, true).encode(base: N), H + [0x0B, 0x09, 0x05, 0x7F, 0xF7])
        XCTAssertEqual(DLiveCommand.getPreampPad(s).encode(base: N), H + [0x0B, 0x07, 0x05, 0xF7])
        XCTAssertEqual(DLiveCommand.preamp48V(s, true).encode(base: N), H + [0x0B, 0x0C, 0x05, 0x7F, 0xF7])
        XCTAssertEqual(DLiveCommand.getPreamp48V(s).encode(base: N), H + [0x0B, 0x0A, 0x05, 0xF7])
        XCTAssertEqual(PreampSocket(mp: 0x40).description, "DX1/2 1")
        XCTAssertEqual(PreampSocket(mp: 0x7F).description, "DX3/4 32")
    }

    func testEQ() {
        let a = ChannelAddress(.input, 0)
        XCTAssertEqual(DLiveCommand.peq(a, band: 0, .type, 0).encode(base: N)[5], 0x1A)
        XCTAssertEqual(DLiveCommand.peq(a, band: 2, .frequency, 0).encode(base: N)[5], 0x23)
        XCTAssertEqual(DLiveCommand.hpfOn(a, true).encode(base: N), [0xBB, 0x63, 0x00, 0xBB, 0x62, 0x31, 0xBB, 0x06, 0x7F])
        // Spec table: 20Hz 00, 50Hz 10, 100Hz 1D, 500Hz 3B, 1kHz 47, 10kHz 72, 20kHz 7F
        XCTAssertEqual([20, 50, 100, 500, 1000, 10000, 20000].map { EQLaw.peqFrequency(Double($0)) },
                       [0x00, 0x10, 0x1D, 0x3B, 0x47, 0x72, 0x7F])
        // Spec table: -15 00, -10 15, -5 2A, 0 3F, 5 54, 10 69, 15 7F
        XCTAssertEqual([-15, -10, -5, 0, 5, 10, 15].map { EQLaw.peqGain(Double($0)) },
                       [0x00, 0x15, 0x2A, 0x3F, 0x54, 0x69, 0x7E])
    }

    func testRecall() {
        XCTAssertEqual(DLiveCommand.recallScene(1).encode(base: N), [0xBB, 0x00, 0x00, 0xCB, 0x00])
        XCTAssertEqual(DLiveCommand.recallScene(129).encode(base: N), [0xBB, 0x00, 0x01, 0xCB, 0x00])
        XCTAssertEqual(DLiveCommand.recallScene(500).encode(base: N), [0xBB, 0x00, 0x03, 0xCB, 0x73])
        XCTAssertEqual(DLiveCommand.recallCue(1999).encode(base: N), [0xBB, 0x00, 0x0F, 0xCB, 0x4F])
        XCTAssertEqual(DLiveCommand.ufxKey(.fSharp).encode(base: N), [0xBB, 0x0C, 0x06])
        XCTAssertEqual(DLiveCommand.ufxScale(.minor).encode(base: N), [0xBB, 0x0D, 0x01])
    }

    func testFaderLawMatchesSpecTable() {
        // dBu -> hex from the spec's "Fader Level" table
        let table: [(Double, UInt8)] = [(10, 0x7F), (0, 0x6B), (-5, 0x61), (-10, 0x57), (-15, 0x4D),
                                        (-20, 0x43), (-25, 0x39), (-30, 0x2F), (-35, 0x25), (-40, 0x1B), (-45, 0x11)]
        for (db, hex) in table {
            XCTAssertEqual(FaderLaw.value(fromDB: db), hex, "\(db) dB")
        }
        XCTAssertEqual(FaderLaw.value(fromDB: -100), 0)
        XCTAssertNil(FaderLaw.dB(from: 0))
        XCTAssertEqual(FaderLaw.dB(from: 0x6B)!, 0, accuracy: 0.5)
    }

    func testPreampGainLaw() {
        XCTAssertEqual(PreampGainLaw.value(fromDB: 5), 0x00)
        XCTAssertEqual(PreampGainLaw.value(fromDB: 60), 0x7F)
        XCTAssertEqual(PreampGainLaw.value(fromDB: 15), 0x17)
    }
}

final class ParseTests: XCTestCase {
    func decodeAll(_ bytes: [UInt8], base: UInt8 = 0x0B) -> [DLiveEvent] {
        var p = MIDIStreamParser()
        var d = DLiveDecoder(base: base)
        return p.feed(bytes).compactMap { d.decode($0) }
    }

    func testSpecRunningStatusMuteExample() {
        // "With running status – Shorter message string 9B, 00, 7F, 01, 7F, 02, 7F"
        XCTAssertEqual(decodeAll([0x9B, 0x00, 0x7F, 0x01, 0x7F, 0x02, 0x7F]),
                       (0..<3).map { .mute(ChannelAddress(.input, $0), true) })
    }

    func testMuteVelocityRules() {
        // 01-3F = off, 40-7F = on, 00 ignored
        XCTAssertEqual(decodeAll([0x9B, 0x05, 0x01, 0x05, 0x40, 0x05, 0x00]),
                       [.mute(ChannelAddress(.input, 5), false), .mute(ChannelAddress(.input, 5), true)])
    }

    func testChunkedNRPNWithRunningStatus() {
        var p = MIDIStreamParser()
        var d = DLiveDecoder(base: 0x0B)
        var events: [DLiveEvent] = []
        for chunk in [[0xBB, 0x63], [0x00, 0x62, 0x17], [0x06], [0x6B]] as [[UInt8]] {
            for m in p.feed(chunk) { if let e = d.decode(m) { events.append(e) } }
        }
        XCTAssertEqual(events, [.level(ChannelAddress(.input, 0), 0x6B)])
    }

    func testRoundTrips() {
        let N: UInt8 = 0x0B
        let a = ChannelAddress(.input, 9)
        let to = ChannelAddress(.stereoAux, 2)
        let cases: [(DLiveCommand, DLiveEvent)] = [
            (.mute(ChannelAddress(.dca, 3), true), .mute(ChannelAddress(.dca, 3), true)),
            (.level(a, 0x50), .level(a, 0x50)),
            (.mainAssign(a, true), .mainAssign(a, true)),
            (.dcaAssign(a, dca: 5, assigned: true), .dcaAssign(a, dca: 5, assigned: true)),
            (.muteGroupAssign(a, group: 2, assigned: false), .muteGroupAssign(a, group: 2, assigned: false)),
            (.sendLevel(from: a, to: to, 0x33), .sendLevel(from: a, to: to, 0x33)),
            (.sendAssign(from: a, to: to, true), .sendAssign(from: a, to: to, true)),
            (.setName(a, "Kick"), .name(a, "Kick")),
            (.setColour(a, .green), .colour(a, 2)),
            (.preampGain(PreampSocket(mp: 3), 0x22), .preampGain(PreampSocket(mp: 3), 0x22)),
            (.preampPad(PreampSocket(mp: 3), true), .preampPad(PreampSocket(mp: 3), true)),
            (.preamp48V(PreampSocket(mp: 3), true), .preamp48V(PreampSocket(mp: 3), true)),
            (.hpfOn(a, true), .hpfOn(a, true)),
            (.hpfFrequency(a, 0x20), .hpfFrequency(a, 0x20)),
            (.peq(a, band: 1, .width, 0x05), .peq(a, band: 1, .width, 0x05)),
            (.recallScene(300), .recall(bank: 2, program: 43)),
            (.ufxKey(.a), .ufxKey(9)),
        ]
        for (cmd, expected) in cases {
            XCTAssertEqual(decodeAll(cmd.encode(base: N)), [expected], "\(cmd)")
        }
    }

    func testReplies() {
        let H = DLive.sysExHeader
        // Name reply on stereo group 1 (N+1, CH 40), base channel 1
        XCTAssertEqual(decodeAll(H + [0x01, 0x02, 0x40, 0x44, 0x72, 0x75, 0x6D, 0x73, 0xF7], base: 0),
                       [.name(ChannelAddress(.stereoGroup, 0), "Drums")])
        // Colour reply: 0N, 05, CH, Col
        XCTAssertEqual(decodeAll(H + [0x0B, 0x05, 0x01, 0x03, 0xF7]), [.colour(ChannelAddress(.input, 1), 3)])
        // Pad reply: 0N, 08, MP, Pad ; 48V reply: 0N, 0B, MP, 48V
        XCTAssertEqual(decodeAll(H + [0x0B, 0x08, 0x02, 0x7F, 0xF7]), [.preampPad(PreampSocket(mp: 2), true)])
        XCTAssertEqual(decodeAll(H + [0x0B, 0x0B, 0x02, 0x00, 0xF7]), [.preamp48V(PreampSocket(mp: 2), false)])
    }

    func testRealtimeInsideSysEx() {
        var p = MIDIStreamParser()
        XCTAssertEqual(p.feed([0xF0, 0x00, 0xF8, 0x01, 0xF7]), [.system([0xF8]), .sysEx([0xF0, 0x00, 0x01, 0xF7])])
    }

    func testHexParse() {
        XCTAssertEqual(Hex.parse("B0 63 0x01,62"), [0xB0, 0x63, 0x01, 0x62])
        XCTAssertEqual(Hex.parse("b06301"), [0xB0, 0x63, 0x01])
        XCTAssertNil(Hex.parse("zz"))
        XCTAssertNil(Hex.parse("abc"))
    }
}

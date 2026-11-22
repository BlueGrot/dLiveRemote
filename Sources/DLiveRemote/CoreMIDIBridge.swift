import Foundation
import CoreMIDI
import DLiveMIDI

/// Virtual CoreMIDI ports that other Mac apps (DAWs, QLab, MainStage…) can use:
///  - a SOURCE named "<name>"        : everything the mixer sends appears here
///  - a DESTINATION named "<name> In": anything apps send here goes to the mixer
final class CoreMIDIBridge {
    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private var destination = MIDIEndpointRef()
    private var decoder = UMP.Decoder()
    private let lock = NSLock()

    /// Called on the main queue with complete MIDI 1.0 messages received from Mac apps.
    var onMessageFromApps: (([UInt8]) -> Void)?
    private(set) var setupError: String?

    init(name: String) {
        var status = MIDIClientCreateWithBlock(name as CFString, &client) { _ in }
        guard status == noErr else { setupError = "MIDI client error \(status)"; return }

        status = MIDISourceCreateWithProtocol(client, name as CFString, ._1_0, &source)
        guard status == noErr else { setupError = "MIDI source error \(status)"; return }

        status = MIDIDestinationCreateWithProtocol(client, "\(name) In" as CFString, ._1_0, &destination) {
            [weak self] eventList, _ in
            self?.receive(eventList)
        }
        guard status == noErr else { setupError = "MIDI destination error \(status)"; return }
    }

    deinit {
        if destination != 0 { MIDIEndpointDispose(destination) }
        if source != 0 { MIDIEndpointDispose(source) }
        if client != 0 { MIDIClientDispose(client) }
    }

    /// Publish one message from the mixer on the virtual source.
    func publish(_ msg: MIDIMessage) {
        guard source != 0 else { return }
        let words = UMP.words(for: msg)
        guard !words.isEmpty else { return }

        let listSize = MemoryLayout<MIDIEventList>.size + words.count * MemoryLayout<UInt32>.size * 2 + 64
        let raw = UnsafeMutableRawPointer.allocate(byteCount: listSize, alignment: MemoryLayout<MIDIEventList>.alignment)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: MIDIEventList.self, capacity: 1)
        var packet: UnsafeMutablePointer<MIDIEventPacket>? = MIDIEventListInit(list, ._1_0)

        var i = 0
        while i < words.count, let p = packet {
            let n = min(UMP.wordCount(words[i]), words.count - i)
            packet = words.withUnsafeBufferPointer { buf in
                MIDIEventListAdd(list, listSize, p, 0, n, buf.baseAddress! + i)
            }
            i += n
        }
        MIDIReceivedEventList(source, list)
    }

    private func receive(_ eventList: UnsafePointer<MIDIEventList>) {
        var messages: [[UInt8]] = []
        lock.lock()
        for packet in eventList.unsafeSequence() {
            let count = Int(packet.pointee.wordCount)
            let offset = MemoryLayout<MIDIEventPacket>.offset(of: \MIDIEventPacket.words)!
            let wordsPtr = UnsafeRawPointer(packet).advanced(by: offset).assumingMemoryBound(to: UInt32.self)
            messages += decoder.feed(Array(UnsafeBufferPointer(start: wordsPtr, count: count)))
        }
        lock.unlock()
        guard !messages.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            for m in messages { self?.onMessageFromApps?(m) }
        }
    }
}

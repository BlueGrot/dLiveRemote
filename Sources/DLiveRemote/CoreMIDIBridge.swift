import Foundation
import CoreMIDI
import DLiveMIDI

/// Virtual CoreMIDI ports that other Mac apps (DAWs, QLab, MainStage…) can use.
///  - one or more SOURCES (mixer → apps), created/removed by `setSources`
///  - a DESTINATION "<name> In" (apps → mixer)
/// `publish` is thread-safe and may be called from the network queue.
final class CoreMIDIBridge {
    private var client = MIDIClientRef()
    private var destination = MIDIEndpointRef()
    private var sources: [BridgePort: MIDIEndpointRef] = [:]
    private let lock = NSLock()
    private var decoder = UMP.Decoder()
    let baseName: String

    /// Called on the main queue with complete MIDI 1.0 messages received from Mac apps.
    var onMessageFromApps: (([UInt8]) -> Void)?
    private(set) var setupError: String?

    init(name: String) {
        baseName = name
        var status = MIDIClientCreateWithBlock(name as CFString, &client) { _ in }
        guard status == noErr else { setupError = "MIDI client error \(status)"; return }

        status = MIDIDestinationCreateWithProtocol(client, "\(name) In" as CFString, ._1_0, &destination) {
            [weak self] eventList, _ in
            self?.receive(eventList)
        }
        if status != noErr { setupError = "MIDI destination error \(status)" }
    }

    deinit {
        for (_, s) in sources { MIDIEndpointDispose(s) }
        if destination != 0 { MIDIEndpointDispose(destination) }
        if client != 0 { MIDIClientDispose(client) }
    }

    /// Create / remove virtual sources so exactly `wanted` exist (port → display name).
    func setSources(_ wanted: [BridgePort: String]) {
        guard client != 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        for (port, ref) in sources where wanted[port] == nil {
            MIDIEndpointDispose(ref)
            sources[port] = nil
        }
        for (port, name) in wanted where sources[port] == nil {
            var ref = MIDIEndpointRef()
            let status = MIDISourceCreateWithProtocol(client, name as CFString, ._1_0, &ref)
            if status == noErr {
                sources[port] = ref
            } else {
                setupError = "Could not create MIDI port \"\(name)\" (\(status))"
            }
        }
    }

    /// Publish one message on a virtual source. Returns false if that port doesn't exist.
    @discardableResult
    func publish(_ msg: MIDIMessage, on port: BridgePort) -> Bool {
        lock.lock()
        let ref = sources[port]
        lock.unlock()
        guard let ref else { return false }

        let words = UMP.words(for: msg)
        guard !words.isEmpty else { return false }

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
        MIDIReceivedEventList(ref, list)
        return true
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

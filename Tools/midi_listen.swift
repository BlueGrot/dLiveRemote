// Listens on a CoreMIDI source and prints what arrives, to verify the bridge from outside the app.
// Usage: swift Tools/midi_listen.swift [source-name-prefix] [seconds]
import Foundation
import CoreMIDI

let args = CommandLine.arguments
let wanted = args.count > 1 ? args[1] : "dLive"
let seconds = args.count > 2 ? Double(args[2]) ?? 10 : 10

func name(_ e: MIDIEndpointRef) -> String {
    var cf: Unmanaged<CFString>?
    MIDIObjectGetStringProperty(e, kMIDIPropertyDisplayName, &cf)
    return (cf?.takeRetainedValue() as String?) ?? "?"
}

var client = MIDIClientRef()
MIDIClientCreateWithBlock("listener" as CFString, &client) { _ in }
var port = MIDIPortRef()
var count = 0
MIDIInputPortCreateWithProtocol(client, "in" as CFString, ._1_0, &port) { list, _ in
    for packet in list.unsafeSequence() {
        let n = Int(packet.pointee.wordCount)
        let off = MemoryLayout<MIDIEventPacket>.offset(of: \MIDIEventPacket.words)!
        let p = UnsafeRawPointer(packet).advanced(by: off).assumingMemoryBound(to: UInt32.self)
        let words = UnsafeBufferPointer(start: p, count: n).map { String(format: "%08X", $0) }
        count += 1
        print("RX UMP:", words.joined(separator: " "))
        fflush(stdout)
    }
}

print("Sources:")
var found = false
for i in 0..<MIDIGetNumberOfSources() {
    let src = MIDIGetSource(i)
    let n = name(src)
    print(" -", n)
    if n == wanted {
        MIDIPortConnectSource(port, src, nil)
        found = true
    }
}
print(found ? "Listening to \"\(wanted)\" for \(seconds)s" : "Source \"\(wanted)\" NOT FOUND")
fflush(stdout)
RunLoop.main.run(until: Date().addingTimeInterval(seconds))
print("Received \(count) packets")
exit(found && count > 0 ? 0 : 1)

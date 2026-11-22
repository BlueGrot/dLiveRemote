import SwiftUI
import DLiveMIDI

struct MonitorView: View {
    @EnvironmentObject var model: MixerModel
    @State private var rawText = ""
    @State private var rawError = false
    @State private var showPartials = false
    @State private var autoscroll = true

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private var entries: [LogEntry] {
        showPartials ? model.log : model.log.filter { !$0.isPartial }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("MIDI Monitor").font(.headline)
                Spacer()
                Toggle("Show NRPN parts", isOn: $showPartials)
                Toggle("Auto-scroll", isOn: $autoscroll)
                Toggle("Pause", isOn: $model.logPaused)
                Button("Clear") { model.clearLog() }
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            ScrollViewReader { proxy in
                List(entries) { e in
                    HStack(spacing: 10) {
                        Text(Self.timeFormat.string(from: e.time))
                            .foregroundStyle(.secondary)
                        Text(e.direction == .tx ? "TX" : "RX")
                            .bold()
                            .foregroundStyle(e.direction == .tx ? Color.blue : Color.green)
                        Text(e.hex)
                            .frame(minWidth: 260, alignment: .leading)
                            .textSelection(.enabled)
                        Text(e.text).foregroundStyle(.secondary)
                    }
                    .font(.system(.caption, design: .monospaced))
                    .id(e.id)
                }
                .onChange(of: model.log.count) { _ in
                    if autoscroll, let last = entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()
            HStack {
                Text("Send raw MIDI (hex):")
                TextField("e.g. BB 63 00 BB 62 17 BB 06 6B", text: $rawText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(sendRaw)
                    .border(rawError ? Color.red : Color.clear)
                Button("Send", action: sendRaw)
                    .disabled(!model.isConnected)
            }
            .padding(8)
        }
    }

    private func sendRaw() {
        guard let bytes = Hex.parse(rawText), !bytes.isEmpty else {
            rawError = true
            return
        }
        rawError = false
        model.sendRaw(bytes)
    }
}

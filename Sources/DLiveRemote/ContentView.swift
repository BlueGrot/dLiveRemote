import SwiftUI
import DLiveMIDI

struct ContentView: View {
    @EnvironmentObject var model: MixerModel

    private var kindSelection: Binding<ChannelKind?> {
        Binding(get: { model.selectedKind }, set: { if let k = $0 { model.selectedKind = k } })
    }

    var body: some View {
        VStack(spacing: 0) {
            ConnectionBar()
            Divider()
            NavigationSplitView {
                List(ChannelKind.allCases, selection: kindSelection) { kind in
                    Text(kind.displayName).tag(kind)
                }
                .navigationSplitViewColumnWidth(min: 150, ideal: 170)
            } detail: {
                VSplitView {
                    VStack(spacing: 0) {
                        StripToolbar()
                        Divider()
                        StripsView(kind: model.selectedKind)
                    }
                    .frame(minHeight: 340)
                    MonitorView()
                        .frame(minHeight: 160)
                }
            }
        }
    }
}

// MARK: - Connection bar

struct ConnectionBar: View {
    @EnvironmentObject var model: MixerModel

    var body: some View {
        HStack(spacing: 12) {
            statusDot
            TextField("MixRack / Surface IP", text: $model.host)
                .textFieldStyle(.roundedBorder)
                .frame(width: 170)
                .disabled(model.connectionState.isActive)
            TextField("Port", value: $model.port, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .disabled(model.connectionState.isActive)
            Toggle("TLS", isOn: $model.useTLS)
                .disabled(model.connectionState.isActive)
                .onChange(of: model.useTLS) { tls in
                    if model.port == Int(DLive.tcpPort) || model.port == Int(DLive.tlsPort) {
                        model.port = Int(tls ? DLive.tlsPort : DLive.tcpPort)
                    }
                }
            Stepper("MIDI ch \(model.baseChannel)–\(model.baseChannel + 4)",
                    value: $model.baseChannel, in: 1...12)
                .help("Base MIDI channel N set on the dLive under Utility › Control › MIDI. N to N+4 are used.")
                .disabled(model.connectionState.isActive)
            Spacer()
            Text(statusText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            if model.connectionState.isActive {
                Button("Disconnect") { model.disconnect() }
            } else {
                Button("Connect") { model.connect() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusDot: some View {
        Circle()
            .fill(dotColour)
            .frame(width: 10, height: 10)
    }

    private var dotColour: Color {
        switch model.connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .failed: return .red
        case .disconnected: return .gray
        }
    }

    private var statusText: String {
        switch model.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .disconnected: return "Disconnected"
        case .failed(let msg): return msg
        }
    }
}

// MARK: - Toolbar above strips

struct StripToolbar: View {
    @EnvironmentObject var model: MixerModel
    @State private var scene = 1

    var body: some View {
        HStack(spacing: 12) {
            Text(model.selectedKind.displayName).font(.headline)
            Button {
                model.refresh(model.selectedKind)
            } label: {
                Label("Refresh from mixer", systemImage: "arrow.clockwise")
            }
            .disabled(model.connectionState != .connected)
            Spacer()
            Text("Scene")
            TextField("", value: $scene, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
            Stepper("", value: $scene, in: 1...500).labelsHidden()
            Button("Recall") { model.send(.recallScene(scene)) }
                .disabled(model.connectionState != .connected)
            if let s = model.lastScene {
                Text("Last: \(s)").foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

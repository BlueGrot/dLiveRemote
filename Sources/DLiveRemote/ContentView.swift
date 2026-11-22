import SwiftUI
import DLiveMIDI

struct ContentView: View {
    @EnvironmentObject var model: MixerModel

    private var pageSelection: Binding<Page?> {
        Binding(get: { model.page }, set: { if let p = $0 { model.page = p } })
    }

    var body: some View {
        VStack(spacing: 0) {
            ConnectionBar()
            Divider()
            NavigationSplitView {
                List(selection: pageSelection) {
                    Section("Channels") {
                        ForEach(ChannelKind.allCases) { kind in
                            Text(kind.displayName).tag(Page.channels(kind))
                        }
                    }
                    Section("MixRack") {
                        Text("Preamps").tag(Page.preamps)
                    }
                }
                .navigationSplitViewColumnWidth(min: 150, ideal: 170)
            } detail: {
                VSplitView {
                    VStack(spacing: 0) {
                        PageToolbar()
                        Divider()
                        switch model.page {
                        case .channels(let kind): StripsView(kind: kind)
                        case .preamps: PreampsView()
                        }
                    }
                    .frame(minHeight: 340)
                    MonitorView()
                        .frame(minHeight: 160)
                }
            }
        }
        .onChange(of: model.page) { p in model.refresh(p) }
    }
}

// MARK: - Connection bar

struct ConnectionBar: View {
    @EnvironmentObject var model: MixerModel

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(dotColour).frame(width: 10, height: 10)
            settings.disabled(model.connectionState.isActive)
            Spacer(minLength: 8)
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

    private var settings: some View {
        HStack(spacing: 12) {
            Picker("", selection: $model.target) {
                ForEach(DLive.Target.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
            TextField("IP address", text: $model.host)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
            Toggle("TLS", isOn: $model.useTLS)
            if model.useTLS {
                Stepper("Profile \(model.userProfile)", value: $model.userProfile, in: 0...31)
                    .help("dLive user profile number (sent as 00–1F)")
                SecureField("Password", text: $model.password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
            }
            Text("port \(String(model.port))").foregroundStyle(.secondary).monospacedDigit()
            Stepper("MIDI \(model.baseChannel)–\(model.baseChannel + 4)",
                    value: $model.baseChannel, in: 1...12)
                .help("Base MIDI channel N from Utility / Control / MIDI. N to N+4 are used.")
        }
    }

    private var dotColour: Color {
        switch model.connectionState {
        case .connected: return .green
        case .connecting, .authenticating: return .yellow
        case .failed: return .red
        case .disconnected: return .gray
        }
    }

    private var statusText: String {
        switch model.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .authenticating: return "Authenticating…"
        case .disconnected: return "Disconnected"
        case .failed(let msg): return msg
        }
    }
}

// MARK: - Toolbar above the page

struct PageToolbar: View {
    @EnvironmentObject var model: MixerModel
    @State private var scene = 1
    @State private var cue = 0

    var body: some View {
        HStack(spacing: 10) {
            Text(model.page.title).font(.headline)
            Button {
                model.refresh(model.page)
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(!model.isConnected)
            Spacer()
            if model.target == .mixRack {
                Text("Scene")
                TextField("", value: $scene, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder).frame(width: 52)
                Stepper("", value: $scene, in: 1...500).labelsHidden()
                Button("Recall") { model.send(.recallScene(scene)) }
                    .disabled(!model.isConnected)
            } else {
                Text("Cue Recall Id")
                TextField("", value: $cue, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder).frame(width: 56)
                Stepper("", value: $cue, in: 0...1999).labelsHidden()
                Button("Recall") { model.send(.recallCue(cue)) }
                    .disabled(!model.isConnected)
            }
            if let r = model.lastRecall {
                Text("Last: \(r)").foregroundStyle(.secondary).monospacedDigit()
            }
            Menu("UFX") {
                Menu("Global Key") {
                    ForEach(UFXKey.allCases) { k in Button(k.name) { model.send(.ufxKey(k)) } }
                }
                Menu("Global Scale") {
                    ForEach(UFXScale.allCases) { s in Button(s.name) { model.send(.ufxScale(s)) } }
                }
            }
            .frame(width: 70)
            .disabled(!model.isConnected)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

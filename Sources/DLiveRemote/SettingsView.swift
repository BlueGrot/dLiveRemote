import SwiftUI
import DLiveMIDI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            RoutingSettings().tabItem { Label("Routing", systemImage: "arrow.triangle.branch") }
            ChannelMapSettings().tabItem { Label("Channels", systemImage: "number") }
            TranslationSettings().tabItem { Label("Translation", systemImage: "arrow.left.arrow.right") }
        }
        .frame(width: 560, height: 470)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @EnvironmentObject var model: MixerModel

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Connect automatically when the app starts", isOn: $model.autoConnectOnLaunch)
                if model.useTLS {
                    Text("With TLS, the password isn't stored, so auto-connect is skipped until you connect once by hand.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                if let err = model.launchAtLoginError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                Toggle("Show in menu bar", isOn: $model.showInMenuBar)
                Toggle("Hide Dock icon (menu bar only)", isOn: $model.hideDockIcon)
            }
            Section("Connection") {
                Toggle("Reconnect automatically", isOn: $model.autoReconnect)
                Toggle("Request mixer state on connect", isOn: $model.refreshOnConnect)
                Text("The replies are also forwarded to Mac apps unless SysEx and fader categories are filtered out.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Alerts") {
                Toggle("Notify when the connection is lost or restored", isOn: $model.notifyOnConnectionChange)
                Picker("Alert when no MIDI arrives for", selection: $model.silenceAlertMinutes) {
                    Text("Off").tag(0)
                    ForEach([1, 2, 5, 10, 15, 30, 60], id: \.self) { Text("\($0) min").tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Routing (filters + per-type ports)

struct RoutingSettings: View {
    @EnvironmentObject var model: MixerModel

    var body: some View {
        Form {
            Section {
                ForEach(MessageCategory.allCases) { cat in
                    Toggle(cat.displayName, isOn: Binding(
                        get: { model.bridgeSettings.forwardedCategories.contains(cat) },
                        set: { on in
                            if on { model.bridgeSettings.forwardedCategories.insert(cat) }
                            else { model.bridgeSettings.forwardedCategories.remove(cat) }
                        }))
                }
            } header: {
                Text("Forward from mixer to Mac")
            } footer: {
                Text("MIDI Strips & custom = anything on MIDI channels outside \(model.baseChannel)–\(model.baseChannel + 4).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Also publish each type on its own MIDI port", isOn: $model.bridgeSettings.splitPorts)
                if model.bridgeSettings.splitPorts {
                    Text(MessageCategory.allCases
                        .filter { model.bridgeSettings.forwardedCategories.contains($0) }
                        .map { "\"\(MixerModel.midiPortName) \($0.portSuffix)\"" }
                        .joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text("The main port \"\(MixerModel.midiPortName)\" always carries everything that's enabled above.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Channel remapping

struct ChannelMapSettings: View {
    @EnvironmentObject var model: MixerModel

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], alignment: .leading) {
                    ForEach(0..<16, id: \.self) { ch in
                        Picker("Ch \(ch + 1) →", selection: Binding(
                            get: { Int(model.bridgeSettings.channelMap[ch]) },
                            set: { model.bridgeSettings.channelMap[ch] = UInt8($0) })) {
                            ForEach(0..<16, id: \.self) { Text("\($0 + 1)").tag($0) }
                        }
                        .fontWeight(isControlChannel(ch) ? .bold : .regular)
                    }
                }
                Button("Reset to 1:1") { model.bridgeSettings.channelMap = Array(0...15) }
                    .disabled(model.bridgeSettings.isIdentityMap)
            } header: {
                Text("MIDI channel sent to Mac apps")
            } footer: {
                Text("Applies to messages forwarded to Mac apps (main and per-type ports). Bold = dLive control channels \(model.baseChannel)–\(model.baseChannel + 4). SysEx is unchanged; MSC and Mackie use their own channels.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func isControlChannel(_ ch: Int) -> Bool {
        let base = model.baseChannel - 1
        return ch >= base && ch <= base + 4
    }
}

// MARK: - Translation

struct TranslationSettings: View {
    @EnvironmentObject var model: MixerModel
    @State private var oscPortText = ""

    var body: some View {
        Form {
            Section {
                Toggle("Send MIDI Show Control GO on scene / cue recall", isOn: $model.bridgeSettings.msc.enabled)
                if model.bridgeSettings.msc.enabled {
                    Picker("Device ID", selection: $model.bridgeSettings.msc.deviceID) {
                        Text("All call (7F)").tag(UInt8(0x7F))
                        ForEach(0..<0x70, id: \.self) { Text(String(format: "%d (%02X)", $0, $0)).tag(UInt8($0)) }
                    }
                    Picker("Command format", selection: $model.bridgeSettings.msc.commandFormat) {
                        Text("All types (7F)").tag(UInt8(0x7F))
                        Text("Lighting (01)").tag(UInt8(0x01))
                        Text("Sound (10)").tag(UInt8(0x10))
                        Text("Video (50)").tag(UInt8(0x50))
                    }
                    TextField("Cue list (optional)", text: $model.bridgeSettings.msc.cueList)
                }
            } header: {
                Text("MIDI Show Control → port \"\(MixerModel.midiPortName) MSC\"")
            } footer: {
                Text("Cue number = scene number (MixRack) or Recall Id (Surface). Works with QLab's MSC triggers.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Send OSC over UDP", isOn: $model.bridgeSettings.osc.enabled)
                if model.bridgeSettings.osc.enabled {
                    TextField("Host", text: $model.bridgeSettings.osc.host)
                    TextField("Port", value: $model.bridgeSettings.osc.port, format: .number.grouping(.never))
                    TextField("On recall send", text: $model.bridgeSettings.osc.recallAddress)
                    Text("{n} = scene / Recall Id. QLab: /cue/{n}/start on port 53000.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Also send /dlive/mute, /dlive/fader, /dlive/name and /dlive/midi", isOn: $model.bridgeSettings.osc.sendEvents)
                }
            } header: {
                Text("OSC")
            }

            Section {
                Toggle("Translate MIDI Strips to Mackie Control", isOn: $model.bridgeSettings.mackie.enabled)
                if model.bridgeSettings.mackie.enabled {
                    channelPicker("Strip faders on MIDI channel", $model.bridgeSettings.mackie.faderChannel)
                    channelPicker("Strip rotaries on MIDI channel", $model.bridgeSettings.mackie.rotaryChannel)
                    channelPicker("Strip keys on MIDI channel", $model.bridgeSettings.mackie.keyChannel)
                }
            } header: {
                Text("Mackie Control → ports \"\(MixerModel.midiPortName) Mackie 1-8\" … \"25-32\"")
            } footer: {
                Text("Faders → MCU faders, Pan rotary → V-Pots, Mute/Mix/PAFL keys → Mute/Select/Solo. One-way only (no motor-fader feedback). Defaults match the dLive template MIDI Strips (faders B1, rotaries B2, keys 91).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func channelPicker(_ title: String, _ value: Binding<UInt8>) -> some View {
        Picker(title, selection: Binding(get: { Int(value.wrappedValue) }, set: { value.wrappedValue = UInt8($0) })) {
            ForEach(0..<16, id: \.self) { Text("\($0 + 1)").tag($0) }
        }
    }
}

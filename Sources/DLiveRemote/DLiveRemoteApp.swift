import SwiftUI
import AppKit
import DLiveMIDI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // .regular is also needed when launched via `swift run` (no .app bundle).
        let hideDock = UserDefaults.standard.bool(forKey: "hideDockIcon")
        NSApp.setActivationPolicy(hideDock ? .accessory : .regular)
        if !hideDock { NSApp.activate(ignoringOtherApps: true) }
        MainActor.assumeIsolated { MixerModel.shared.didFinishLaunching() }
    }

    /// Keep bridging MIDI when the window is closed; quit with ⌘Q or from the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct DLiveRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Not observed here on purpose: observing the model at App level re-evaluates every
    /// scene on each change, which loops with MenuBarExtra and crashes on recent macOS.
    private let model = MixerModel.shared
    /// Mirrors MixerModel.showInMenuBar (same UserDefaults key) so the scene updates
    /// without the App observing the whole model.
    @AppStorage("showInMenuBar") private var showInMenuBar = true

    var body: some Scene {
        WindowGroup("dLive Remote", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1100, minHeight: 640)
        }
        .commands { MixerCommands(model: model) }

        Settings {
            SettingsView()
                .environmentObject(model)
        }

        MenuBarExtra(isInserted: Binding(
            get: { showInMenuBar },
            set: { if showInMenuBar != $0 { showInMenuBar = $0 } }
        )) {
            MenuBarContent()
                .environmentObject(model)
        } label: {
            MenuBarLabel(model: model)
        }
    }
}

struct MixerCommands: Commands {
    @ObservedObject var model: MixerModel

    var body: some Commands {
        CommandMenu("Mixer") {
            Button("Connect") { model.connect() }
                .keyboardShortcut("k", modifiers: [.command])
                .disabled(model.connectionState.isActive)
            Button("Disconnect") { model.disconnect() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(!model.connectionState.isActive)
            Divider()
            Button("Refresh Current Page") { model.refresh(model.page) }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!model.isConnected)
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: MixerModel
    var body: some View {
        Image(systemName: model.isConnected ? "pianokeys.inverse" : "pianokeys")
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var model: MixerModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusLine)
        Text("→ Mac: \(model.forwardedToMac) messages")
        Divider()
        if model.connectionState.isActive || model.isReconnecting {
            Button("Disconnect") { model.disconnect() }
        } else {
            Button("Connect to \(model.host)") { model.connect() }
        }
        Toggle("Mixer → Mac", isOn: $model.forwardToMac)
        Toggle("Mac → Mixer", isOn: $model.forwardFromMac)
        Divider()
        Button("Open dLive Remote") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        if #available(macOS 14.0, *) {
            SettingsLink { Text("Settings…") }
        }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        switch model.connectionState {
        case .connected: return "Connected to \(model.target.displayName) \(model.host)"
        case .connecting: return "Connecting…"
        case .authenticating: return "Authenticating…"
        case .disconnected: return "Disconnected"
        case .failed(let m): return model.isReconnecting ? "Reconnecting… (\(m))" : m
        }
    }
}

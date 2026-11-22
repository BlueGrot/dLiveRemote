import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched via `swift run` (no .app bundle) so the window comes to front.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Keep bridging MIDI when the window is closed; quit with ⌘Q.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct DLiveRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = MixerModel()

    var body: some Scene {
        WindowGroup("dLive Remote") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .commands {
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
}

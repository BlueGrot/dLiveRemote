# dLive Remote — notes for Claude

macOS app (SwiftUI, macOS 13+, Swift package) that bridges MIDI over TCP/IP from an Allen & Heath
dLive mixer to other Mac apps via virtual CoreMIDI ports. **Main function: mixer → Mac.**
See README.md for features and settings.

## Layout
- `Sources/DLiveMIDI/` — pure protocol library (Linux-buildable, unit-tested):
  `DLiveProtocol.swift` (all constants from the "dLive MIDI Over TCP/IP Protocol V2.0" PDF),
  `MIDIStreamParser.swift`, `UMP.swift`, `BridgeRouter.swift` (filters / per-type ports /
  channel map / MSC / OSC / Mackie), `OSC.swift`, `DLiveConnection.swift` (Network.framework, TLS auth).
- `Sources/DLiveRemote/` — app: `MixerModel` (shared singleton, `MixerModel.shared`),
  `BridgeEngine` (forwards on the network queue, not the main thread), `CoreMIDIBridge`
  (virtual sources "dLive", "dLive <Type>", "dLive MSC", "dLive Mackie …"; destination "dLive In"),
  views, `SettingsView`, menu bar extra.
- `Tools/mock_dlive.py` — mock mixer (`--simulate` sends faders/mutes/recalls/MIDI strips).
- `Tools/midi_listen.swift` — prints what arrives on a CoreMIDI source.
- CI: `.github/workflows/build-macos.yml` (tests + .app), `run-app.yml` (launches app against the
  mock and checks MIDI reaches the "dLive" port).

## Build / run / test
```bash
swift test
./Scripts/make-app.sh                     # → build/DLiveRemote.app (ad-hoc signed)
python3 Tools/mock_dlive.py --simulate    # mock MixRack on :51325, MIDI ch 12
swift Tools/midi_listen.swift dLive 15    # verify the bridge from outside the app
```

## Rules learned the hard way
- **Do not observe `MixerModel` from the `App` struct** (`@ObservedObject`/`@StateObject` there).
  It re-evaluates every scene on each change and, with `MenuBarExtra(isInserted:)`, recursed until a
  stack overflow on macOS 27 (crash in `View.keyboardShortcut` inside `DLiveRemoteApp.body`).
  Observe the model only inside views / `Commands` structs.
- Auto-connect runs from `AppDelegate.applicationDidFinishLaunching` → `MixerModel.shared.didFinishLaunching()`.
- macOS 27's `xattr` has no `-r`; use `find … -exec xattr -c {} \;`.

## Current status (handoff from cloud session, 2026-11-22)
- Fix for the launch crash is on `main` (commit "Fix launch crash: infinite SwiftUI scene update loop").
  It passes CI end-to-end on GitHub's macOS runner, but **has not yet been confirmed on the user's
  Mac (macOS 27.2.1, Apple Silicon)**, where the crash happened.
- The user then got "The application can't be opened. -47". `/Applications/DLiveRemote.app` appears to
  be a broken/partial copy (Spotlight lists it, but `Contents/MacOS` is missing).

## Next steps
1. `rm -rf /Applications/DLiveRemote.app`
2. `./Scripts/make-app.sh` (needs Xcode or Command Line Tools), then
   `ditto build/DLiveRemote.app /Applications/DLiveRemote.app`
3. Launch from Terminal to see errors: `/Applications/DLiveRemote.app/Contents/MacOS/DLiveRemote`
   (also try `open /Applications/DLiveRemote.app`). If it crashes, read the newest
   `~/Library/Logs/DiagnosticReports/DLiveRemote-*.ips` and fix.
4. Verify end-to-end with the mock + `Tools/midi_listen.swift`, then with the real dLive if available.

# dLive Remote

A macOS app (SwiftUI, macOS 13+) that sends and receives MIDI over TCP/IP to an Allen & Heath dLive MixRack or Surface.

## Mixer → Mac MIDI bridge (main function)

While the app is connected, it creates two virtual MIDI ports that any Mac app can use (Logic, Ableton, Reaper, QLab, MainStage and so on):

| Port | In your other app, choose it as | Carries |
|---|---|---|
| **dLive** | a MIDI *input* | everything the mixer sends: MIDI strips, scene/cue recalls, mutes, faders, names and so on, forwarded as-is |
| **dLive In** | a MIDI *output* | anything the app sends, which is passed on to the mixer |

- The two directions can be switched on and off separately ("Mixer → Mac" and "Mac → Mixer").
- If the connection drops, the app reconnects automatically every 3 seconds.
- The app stops macOS from throttling it (App Nap) while connected.
- Closing the window keeps the bridge running; quit with ⌘Q.
- "Request state on connect" is off by default, because the mixer's replies would also flood your DAW's input.


- Connects to a **MixRack** (TCP 51325, or TLS 51327) or a **Surface** (TCP 51328, or TLS 51329).
- TLS logins send the dLive user profile (0–31) and password, then wait for the console's `AuthOK` reply.
- Strip pages for every MIDI channel type: inputs, mono and stereo groups, auxes, matrices, FX sends and returns, mains, DCAs, mute groups, and UFX sends and returns. Each strip has a fader, mute, name, colour and a main-mix assign indicator, all updated live from the console.
- Right-click a strip to rename it, change its colour, assign it to main, turn the HPF on or off, set 0 dB or -∞, assign or unassign DCAs and mute groups, or fetch its state.
- **Preamps** page for MixRack sockets 1–64: gain (+5 to +60 dB), pad and 48V.
- Scene recall 1–500 on a MixRack; cue Recall Id 0–1999 on a Surface; UFX global key and scale.
- **Refresh** (⌘R, and automatically after connecting or changing page) requests the current state of the visible page.
- MIDI monitor with TX/RX hex and a decoded description of each message, plus a raw hex sender.
- Handles MIDI running status, which the dLive uses.

The protocol library (`DLiveMIDI`) also encodes and decodes send levels and assigns, PEQ and HPF frequency. These aren't in the UI yet.

## Build and run

Requires Xcode 15 or later, or the Swift 5.9+ command-line tools.

```bash
swift test               # protocol unit tests (expected bytes taken from the V2.0 spec)
swift run DLiveRemote    # run the app directly
./Scripts/make-app.sh    # build build/DLiveRemote.app (ad-hoc signed)
```

You can also open `Package.swift` in Xcode and run the `DLiveRemote` scheme. On Linux, only the protocol library and its tests are built.

On macOS 15 and later, the first connection triggers a Local Network permission prompt.

## dLive setup

Go to **Utility / Control / MIDI** on the dLive. Set the app's MIDI stepper to that base channel N; the app uses N to N+4. Pick MixRack or Surface and enter its IP address. Scene recall works on the MixRack and cue recall on the Surface.

## Testing without a console

```bash
python3 Tools/mock_dlive.py --simulate            # MixRack port 51325, base channel 12
```

Connect the app to `127.0.0.1` as a MixRack with TLS off. The mock keeps state, answers get requests, relays changes between clients, and with `--simulate` moves random input faders.

## Architecture

```
Sources/DLiveMIDI/          (library, no UI)
  MIDIStreamParser.swift    TCP byte stream → MIDI messages (running status, SysEx, realtime)
  DLiveProtocol.swift       ALL protocol constants, channel map, value laws, encoder and decoder
  DLiveConnection.swift     Network.framework TCP/TLS transport + authentication
Sources/DLiveRemote/        SwiftUI app (MixerModel = state + glue; views)
Tests/DLiveMIDITests/       XCTest, expected bytes from the spec
Tools/mock_dlive.py         mock mixer
```

## Protocol source and open points

Implemented from *dLive MIDI Over TCP/IP Protocol – Firmware V2.0*
(allen-heath.com/content/uploads/2024/06/dLive-MIDI-Over-TCP-Protocol-V2.0.pdf).

- **Authentication bytes:** the spec says only "UserProfile, UserPassword". The app sends one profile byte (00–1F) followed by the password's ASCII bytes, with no separator. If TLS login fails on a real console, check this format first. It's in `DLive.authMessage`.
- **Typos in the spec's tables:** its +5 dB fader entry lists 74 but gives the decimal as 117, which is 0x75. The PEQ gain entry for +15 dB lists 7F but the decimal is 126, which is 0x7E. The code follows the formulas, which match the decimals.

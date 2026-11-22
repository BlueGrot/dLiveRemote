# dLive Remote

A macOS app (SwiftUI, macOS 13+) that sends and receives MIDI over TCP/IP to an Allen & Heath dLive MixRack or Surface.

## Features

- Connect over plain TCP (port 51328) or TLS (port 51329). TLS accepts the dLive's self-signed certificate.
- Strip pages for every MIDI-addressable channel type: inputs, mono and stereo groups, auxes, matrices, FX sends and returns, mains, DCAs, mute groups, and UFX sends and returns.
- Each strip has a fader (NRPN level), a mute button, a name and a colour. All of these update live from the mixer.
- Right-click a strip to rename it, set its colour, set it to 0 dB or -∞, assign or unassign DCAs and mute groups, or fetch its state from the mixer.
- **Refresh from mixer** (⌘R) requests the name, colour, level and mute of every strip on the current page.
- Recall scenes 1–500.
- A MIDI monitor shows every TX and RX message as hex with a decoded description, and has a raw hex sender for any other message.
- The base MIDI channel N is configurable (1–12). The app uses channels N to N+4.

## Build and run

Requires Xcode 15 or later, or the Swift 5.9+ command-line tools.

```bash
swift test               # protocol unit tests
swift run DLiveRemote    # run the app directly
./Scripts/make-app.sh    # build build/DLiveRemote.app (ad-hoc signed)
```

You can also open `Package.swift` in Xcode and run the `DLiveRemote` scheme.

On macOS 15 and later, the first connection to the mixer triggers a Local Network permission prompt. The `.app` bundle includes the required usage string.

## dLive setup

On the dLive, go to **Utility › Control › MIDI**. Note the MIDI channel N and set the app's "MIDI ch" stepper to match. Connect to the MixRack IP, or to the Surface IP.

## Testing without a console

```bash
python3 Tools/mock_dlive.py --simulate     # listens on :51328, base channel 12
```

Then connect the app to `127.0.0.1`. The mock keeps state, answers get requests, relays changes between clients, and with `--simulate` moves random input faders. It mirrors this app's own byte formats, so it can't prove them against a real console.

## Architecture

```
Sources/DLiveMIDI/          (library, no UI)
  MIDIStreamParser.swift    TCP byte stream → MIDI messages (running status, SysEx, realtime)
  DLiveProtocol.swift       ALL protocol constants, channel map, encoder (DLiveCommand) and decoder (DLiveEvent)
  DLiveConnection.swift     Network.framework TCP/TLS transport
Sources/DLiveRemote/        SwiftUI app (MixerModel = state + glue; views)
Tests/DLiveMIDITests/       XCTest for encoding/decoding
Tools/mock_dlive.py         mock mixer
```

## ⚠️ Verify against the V2.0 spec

The protocol PDF couldn't be downloaded while this was being built, so the byte formats come from the Allen & Heath MIDI protocol family as it is generally documented. They have not been checked against *dLive MIDI Over TCP/IP Protocol V2.0*. Every constant is in `Sources/DLiveMIDI/DLiveProtocol.swift`, and the least certain ones are marked `UNVERIFIED`:

| Item | Implemented as | Confidence |
|---|---|---|
| Port | 51328 (TCP), 51329 (TLS) | TCP high, TLS medium |
| TLS authentication handshake | **not implemented**: V2.0 may require a login after the TLS handshake | — |
| Channel map N…N+4 and CH ranges | see `ChannelKind` | high |
| Mute | `9N CH 7F/3F 9N CH 00` | high |
| Fader | NRPN `BN 63 CH BN 62 17 BN 06 LV` | high |
| Fader law | 0x6B = 0 dB, 0x7F = +10 dB, linear in dB | approximate |
| DCA and mute group assign | NRPN param 0x40, values 0x40+/0x00+ and 0x58+/0x18+ | high |
| Name, colour, get requests | SysEx fn 01/02/03, 04/05/06, `05 0B 17` and `05 09` | medium |
| Send level | SysEx fn 0x0D | medium |
| Scene recall | `BN 00 Bank CN Prog` | high |
| Preamp gain, pad and 48V | NRPN 0x19/0x1A/0x1B | low (encoder only, no UI) |
| Colour codes | 0 off, 1 red, 2 green, 3 yellow, 4 blue, 5 purple, 6 light blue, 7 white | medium |

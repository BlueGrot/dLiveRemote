#!/usr/bin/env python3
"""Minimal mock of a dLive MixRack's MIDI-over-TCP interface, for testing without hardware.

    python3 Tools/mock_dlive.py [--port 51325] [--base 12] [--simulate]

- Keeps mute / level / name / colour state for every address.
- Answers get-name / get-colour / get-level / get-mute requests.
- Forwards changes from one client to all *other* connected clients.
- Plain TCP only (no TLS / authentication).
- --simulate sends a fader, mute, scene recall or MIDI Strip message every second.

It implements the same byte formats as Sources/DLiveMIDI/DLiveProtocol.swift. It is a test
double for the app, not a reference for the real console's behaviour.
"""
import argparse
import random
import socket
import threading
import time

HDR = bytes([0xF0, 0x00, 0x00, 0x1A, 0x50, 0x10, 0x01, 0x00])


class Parser:
    """MIDI stream parser with running status and SysEx."""

    def __init__(self):
        self.status = None
        self.data = []
        self.sysex = None

    @staticmethod
    def need(s):
        hi = s & 0xF0
        if hi in (0x80, 0x90, 0xA0, 0xB0, 0xE0):
            return 2
        if hi in (0xC0, 0xD0):
            return 1
        return {0xF1: 1, 0xF3: 1, 0xF2: 2}.get(s, 0)

    def feed(self, chunk):
        out = []
        for b in chunk:
            if b >= 0xF8:
                continue
            if b == 0xF0:
                self.sysex, self.status, self.data = [0xF0], None, []
                continue
            if b == 0xF7:
                if self.sysex is not None:
                    out.append(bytes(self.sysex + [0xF7]))
                self.sysex = None
                continue
            if self.sysex is not None:
                if b & 0x80:
                    self.sysex = None
                else:
                    self.sysex.append(b)
                    continue
            if b & 0x80:
                self.status, self.data = b, []
                if b >= 0xF0 and self.need(b) == 0:
                    self.status = None
                continue
            if self.status is None:
                continue
            self.data.append(b)
            if len(self.data) == self.need(self.status):
                out.append(bytes([self.status] + self.data))
                self.data = []
                if self.status >= 0xF0:
                    self.status = None
        return out


class Mixer:
    def __init__(self, base):
        self.N = base - 1
        self.lock = threading.Lock()
        self.level = {}   # (midi_ch, ch) -> value
        self.nrpn = {}    # (midi_ch, ch, param) -> value  (main assign, HPF, PEQ...)
        self.gain = {}    # mp -> value
        self.pad = {}
        self.phantom = {}
        self.mute = {}
        self.name = {}
        self.colour = {}
        self.clients = []

    def broadcast(self, data, exclude=None):
        for c in list(self.clients):
            if c is exclude:
                continue
            try:
                c.sendall(data)
            except OSError:
                pass


def nrpn(midi, ch, param, value):
    b = 0xB0 | midi
    return bytes([b, 0x63, ch, b, 0x62, param, b, 0x06, value])


def handle(conn, addr, mixer: Mixer):
    print(f"client connected: {addr}", flush=True)
    parser = Parser()
    nrpn_state = {}
    try:
        while True:
            chunk = conn.recv(4096)
            if not chunk:
                break
            for m in parser.feed(chunk):
                print(f"  rx {addr[1]}: {m.hex(' ').upper()}")
                reply = process(m, mixer, nrpn_state, conn)
                if reply:
                    conn.sendall(reply)
                    print(f"  tx {addr[1]}: {reply.hex(' ').upper()}")
    except OSError:
        pass
    finally:
        with mixer.lock:
            if conn in mixer.clients:
                mixer.clients.remove(conn)
        conn.close()
        print(f"client disconnected: {addr}", flush=True)


def process(m, mixer, st, conn):
    s = m[0]
    with mixer.lock:
        if s & 0xF0 == 0x90 and len(m) == 3:
            midi, ch, vel = s & 0x0F, m[1], m[2]
            if vel == 0:
                return None
            mixer.mute[(midi, ch)] = vel >= 0x40
            mixer.broadcast(bytes([s, ch, vel, s, ch, 0]), exclude=conn)
        elif s & 0xF0 == 0xB0 and len(m) == 3:
            midi = s & 0x0F
            cc, v = m[1], m[2]
            if cc == 0x63:
                st[(midi, "msb")] = v
            elif cc == 0x62:
                st[(midi, "lsb")] = v
            elif cc == 0x06:
                ch, param = st.get((midi, "msb")), st.get((midi, "lsb"))
                if ch is not None and param == 0x17:
                    mixer.level[(midi, ch)] = v
                elif ch is not None:
                    mixer.nrpn[(midi, ch, param)] = v
                if ch is not None:
                    mixer.broadcast(nrpn(midi, ch, param, v), exclude=conn)
            elif cc == 0x00:
                st[(midi, "bank")] = v
        elif s & 0xF0 == 0xC0:
            midi = s & 0x0F
            scene = st.get((midi, "bank"), 0) * 128 + m[1] + 1
            print(f"  scene {scene} recalled")
            mixer.broadcast(bytes([0xB0 | midi, 0x00, st.get((midi, 'bank'), 0), s, m[1]]), exclude=conn)
        elif s & 0xF0 == 0xE0 and len(m) == 3:  # preamp gain (pitchbend on N)
            mixer.gain[m[1]] = m[2]
            mixer.broadcast(m, exclude=conn)
        elif m.startswith(HDR):
            body = m[len(HDR):-1]
            if len(body) < 3:
                return None
            midi, fn = body[0] & 0x0F, body[1]
            if fn == 0x03:  # set name
                mixer.name[(midi, body[2])] = body[3:].decode("ascii", "replace")
                mixer.broadcast(m, exclude=conn)
            elif fn == 0x06 and len(body) == 4:  # set colour
                mixer.colour[(midi, body[2])] = body[3]
                mixer.broadcast(m, exclude=conn)
            elif fn == 0x01:  # get name
                ch = body[2]
                nm = mixer.name.get((midi, ch), "").encode("ascii")
                return HDR + bytes([midi, 0x02, ch]) + nm + b"\xF7"
            elif fn == 0x04:  # get colour
                ch = body[2]
                return HDR + bytes([midi, 0x05, ch, mixer.colour.get((midi, ch), 0)]) + b"\xF7"
            elif fn == 0x05 and len(body) == 5 and body[2] == 0x0B:  # get NRPN param
                param, ch = body[3], body[4]
                if param == 0x17:
                    return nrpn(midi, ch, 0x17, mixer.level.get((midi, ch), 0))
                if param == 0x19:  # preamp gain -> pitchbend reply
                    return bytes([0xE0 | midi, ch, mixer.gain.get(ch, 0)])
                default = 0x7F if param == 0x18 else 0
                return nrpn(midi, ch, param, mixer.nrpn.get((midi, ch, param), default))
            elif fn == 0x09 and len(body) == 4:  # set pad
                mixer.pad[body[2]] = body[3] >= 0x40
                mixer.broadcast(m, exclude=conn)
            elif fn == 0x07:  # get pad
                return HDR + bytes([midi, 0x08, body[2], 0x7F if mixer.pad.get(body[2]) else 0]) + b"\xF7"
            elif fn == 0x0C and len(body) == 4:  # set 48V
                mixer.phantom[body[2]] = body[3] >= 0x40
                mixer.broadcast(m, exclude=conn)
            elif fn == 0x0A:  # get 48V
                return HDR + bytes([midi, 0x0B, body[2], 0x7F if mixer.phantom.get(body[2]) else 0]) + b"\xF7"
            elif fn == 0x05 and len(body) == 4 and body[2] == 0x09:  # get mute
                ch = body[3]
                vel = 0x7F if mixer.mute.get((midi, ch)) else 0x3F
                return bytes([0x90 | midi, ch, vel, 0x90 | midi, ch, 0])
            elif fn in (0x0D, 0x0E) and len(body) == 6:
                mixer.broadcast(m, exclude=conn)
    return None


def simulate(mixer):
    """Cycle through typical traffic: fader, mute, scene recall, MIDI Strip fader/key."""
    N = mixer.N
    i = 0
    while True:
        time.sleep(1)
        step = i % 5
        ch = (i // 5) % 8
        if step == 0:
            v = random.randrange(0, 128)
            msg = nrpn(N, ch, 0x17, v)
            mixer.level[(N, ch)] = v
            label = f"input {ch + 1} fader -> {v:#04x}"
        elif step == 1:
            on = not mixer.mute.get((N, ch), False)
            mixer.mute[(N, ch)] = on
            msg = bytes([0x90 | N, ch, 0x7F if on else 0x3F, 0x90 | N, ch, 0])
            label = f"input {ch + 1} mute {'on' if on else 'off'}"
        elif step == 2:
            scene = i // 5 % 20
            msg = bytes([0xB0 | N, 0x00, 0x00, 0xC0 | N, scene])
            label = f"scene {scene + 1} recalled"
        elif step == 3:
            msg = bytes([0xB1, ch, random.randrange(0, 128)])
            label = f"MIDI strip {ch + 1} fader"
        else:
            msg = bytes([0x91, ch, 0x7F, 0x91, ch, 0x00])
            label = f"MIDI strip {ch + 1} mute key"
        with mixer.lock:
            mixer.broadcast(msg)
        print(f"  sim: {label}: {msg.hex(' ').upper()}", flush=True)
        i += 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=51325, help="51325 = MixRack, 51328 = Surface (plain TCP)")
    ap.add_argument("--base", type=int, default=12, help="base MIDI channel N (1-12)")
    ap.add_argument("--simulate", action="store_true")
    args = ap.parse_args()

    mixer = Mixer(args.base)
    for i, n in enumerate(["Kick", "Snare", "HiHat", "Bass", "Gtr", "Keys", "Vox 1", "Vox 2"]):
        mixer.name[(mixer.N, i)] = n
        mixer.colour[(mixer.N, i)] = 1 + i % 7
        mixer.level[(mixer.N, i)] = 0x6B

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", args.port))
    srv.listen()
    print(f"mock dLive listening on :{args.port}, MIDI channels {args.base}-{args.base + 4}", flush=True)
    if args.simulate:
        threading.Thread(target=simulate, args=(mixer,), daemon=True).start()
    while True:
        conn, addr = srv.accept()
        conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        with mixer.lock:
            mixer.clients.append(conn)
        threading.Thread(target=handle, args=(conn, addr, mixer), daemon=True).start()


if __name__ == "__main__":
    main()

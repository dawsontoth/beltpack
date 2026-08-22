# beltpack

Turns a phone and whatever earbuds are already in someone's pocket into a
comms position, alongside the wired Hollyland ring rather than instead of it.

Sibling to [announcer](https://github.com/dawsontoth/announcer): `announcer`
speaks, `beltpack` listens.

## How it fits together

The WING does the mixing. This repo is only a transport.

```
announcer Pi ─┐
stage TB ─────┤                    ┌─ Bus 1 ──► Hollyland ──► 5 wired headsets
board TB ─────┴──►  W I N G  ──────┤
                                   └─ Bus 2 ──► Mac mini ──► Wi-Fi ──► phones
                                      (USB, UAC2 48x48)
```

* **Bus 1 — Comms Mix** goes to the Hollyland base, exactly as it does today.
  Nothing about the wired path changes.
* **Bus 2 — Comms → Phones** is a *mix-minus* feed: identical to Bus 1 except
  it must never contain the phone talk return, or phone users hear themselves
  a quarter-second late and it is unusable.
* Both buses ride the one USB cable already connecting the Mac to the WING.

Talking is off by default and gated in two places: `BELTPACK_CAN_PUBLISH`
decides whether beltpacks may publish at all, and `BELTPACK_SUBSCRIBE` decides
whether the bridge listens for them and returns the sum to the console. Turn on
both for full duplex; leave both off for listen-only.

## Status

Verified end to end on real hardware — a USB microphone standing in for the
console, a self-hosted LiveKit, and an iPhone on Wi-Fi with Bluetooth earbuds:

| | |
|---|---|
| Console &rarr; phone | working, latency good with earbuds |
| Phone &rarr; console | working, latency good |
| Push to talk / latch / open | working |
| Real WING over USB | **untested** — no console on hand |
| TLS via Caddy | **untested** — bench testing has run without it |
| TestFlight distribution | not set up |

## Talking

Four talk modes, set per phone: listen only, hold to talk, tap to latch, or
leave the mic open. Push-to-talk is the default, because ten open mics in a
sanctuary is a different kind of problem.

The microphone is armed when you join, not when you first press: the track is
published already muted, so pressing talk is a local unmute rather than an
audio-session switch, a track creation and a publish negotiation. That matters
because the session switch is what drags Bluetooth from A2DP to HFP, which
takes well over a second on real earbuds — an unacceptable delay on a cue.

The cost of arming is that the earbuds sit in hands-free mode for the whole
service rather than only while you talk. **Listen only** is the mode for anyone
who never talks: it never arms, so Bluetooth stays in A2DP at full quality.

Two microphone modes, and the choice is a real trade rather than a preference.
Asking iOS for the **headset mic** forces Bluetooth into hands-free mode: both
directions drop to 16 kHz mono, the console feed included, in exchange for
roughly 30 ms of latency and the use of both hands. The **phone mic** keeps the
earbuds in A2DP/AAC at full bandwidth, but you hold the handset to talk.

Headset is the default. On comms a cue heard sooner beats a cue heard in higher
fidelity, and a camera operator needs their hands.

Note the asymmetry in audio processing, which is deliberate: the talk track has
echo cancellation, noise suppression and AGC **on**; the console feed has all
three **off**. One is a voice in a loud room, the other is a finished mix, and
the processing that rescues the first wrecks the second.

## Layout

| Path | What it is |
|---|---|
| `server/` | Swift package. `BeltpackKit` holds the shared logic; `BeltpackBridge` is the headless CLI. |
| `mac/` | SwiftUI host app: pick devices, watch participants, start and stop. |
| `ios/` | Swift + XcodeGen. The native app, because iOS Safari suspends WebRTC on lock. |
| `web/` | PWA for Android and booth laptops, where background audio already works. |
| `token/` | Zero-dependency Node service. Trades a passcode for a short-lived token. |
| `deploy/` | LiveKit config, Caddyfile, LaunchAgents, and the console runbook. |

## Quickstart

```bash
make setup-dev     # this laptop: installs tools, writes .env, smoke-tests LiveKit
make setup         # the booth Mac: same, but requires a real LAN address
```

`setup.sh` is idempotent — run it as often as you like. It generates API
credentials and a join passcode on first run, never replaces an existing
secret, and finishes by telling you exactly what is still outstanding. Then:

```bash
make mac           # build and launch the Mac host app
make build         # bridge + PWA
make run-livekit   # in one terminal
make run-token     # in another
make run-bridge    # in a third
make ios           # opens Xcode
```

`make check` builds everything and lints what can be linted.

## Pairing

Nobody should type a server address or a passcode into a phone. Show a code
instead:

```bash
make pair              # iPhone: opens the app via beltpack://
make pair -- --web     # Android and laptops: opens the web client
```

The Mac app has the same thing behind its **Pair** button, showing both codes
side by side.

The passcode travels inside the code, so a printed one is a key: anyone who
photographs it is on comms. The web client scrubs the pairing parameters out of
the address bar as soon as it has read them, so the passcode does not linger in
browser history.

## The Mac host app

`make mac` builds and launches a SwiftUI front end for the same bridge — device
pickers with channel counts, live participant list with mute and speaking
state, and start/stop, plus a menu bar item for glancing at it mid-service.

Prefer it to the CLI on the booth Mac, for a reason beyond convenience: a
bundled app has its own TCC identity, so the microphone prompt is attributed to
Beltpack itself. A bare CLI binary has no identity of its own and its prompt is
attributed to whatever terminal launched it, which is why the headless bridge
needs its permission granted against your terminal app.

It reads the same `.env` as everything else — looking in the obvious places
first, with a file picker if it guesses wrong. Diagnostics go to the unified
log rather than stdout, since a bundled app has nowhere to print:

```bash
make mac-logs
```

## Three things that will bite you

**Grant Microphone permission before anything else.** Capturing the WING counts
as microphone access under macOS TCC. Until it is granted, `make devices` shows
the device with an empty name and the bridge cannot capture:

```
Core Audio inputs (1):
  <no name — grant Microphone permission>  [id: ]
```

Run `make devices` from the terminal you will actually use, approve the prompt,
and confirm the name appears. This is also why the services install as
**LaunchAgents** rather than LaunchDaemons — a daemon has no login session to
prompt in.

**Nothing secret goes in `deploy/livekit.yaml`.** It is a tracked file in a
public repo. Keys and the Mac's LAN address are injected by `deploy/run.sh`
from `.env` as `LIVEKIT_KEYS` and `NODE_IP`. If you find yourself editing
credentials into a committed file, stop.

**The web client needs a real certificate.** Browsers refuse WebRTC and service
workers outside a secure context, and a bare LAN IP is not one. Point a real
hostname's A record at the Mac's private address and let Caddy get a Let's
Encrypt cert over DNS-01. See `deploy/Caddyfile`.

**Publishing a mic costs you AirPods quality.** With no local track published,
AirPods stay in A2DP/AAC at full bandwidth. The moment phase 2 publishes one,
iOS flips them to hands-free mode — 16 kHz mono, in *both* directions. The way
out is `.playAndRecord` with `.allowBluetoothA2DP` (not `.allowBluetooth`) plus
`setPreferredInput()` forced to the built-in mic, so output stays in AAC and
you talk into the phone you are already holding.

## Reconnection

All three clients retry a dropped connection with backoff, capped at 15s, and
stop as soon as somebody deliberately leaves. This matters more than it sounds:
an unassisted access-point roam is the failure most likely to happen in
practice, and before this a dropped connection was permanent — the bridge in
particular stayed alive, connected to nothing, publishing nothing, and silent
about it, which looks healthy from the outside while comms is dead.

A failed microphone no longer presents as a failed connection either. Someone
whose mic is denied or missing still hears the console; the client says so and
hides the talk control rather than claiming comms is down.

## Known issue: virtual audio devices

Some virtual devices (ZoomAudioDevice is one) advertise a perfectly valid
format — 48 kHz, correct channel count, no error status — and then fail when
AVAudioEngine opens them, killing the process with an uncaught ObjC exception:

```
*** Terminating app due to uncaught exception 'com.apple.coreaudio.avfaudio',
    reason: 'Input HW format is invalid'
```

There is no cheap way to detect this in advance; the device only misbehaves
once opened. Real class-compliant hardware is fine — a Yeti X and the WING both
capture normally. If you see this, the last `beltpack-bridge:` line in the log
names the device that did it. Point `BELTPACK_INPUT_DEVICE` somewhere else.

Note that launchd will restart the bridge every 10s in this state, so the log
grows fast.

## What this is not

An in-ear monitor system. Expect roughly 130 ms to wired earbuds and 250 ms to
AirPods. Fine for cues and talkback; nowhere near good enough for a musician
monitoring themselves.

## Ports

| Port | Service |
|---|---|
| 7880 | LiveKit signalling (loopback; Caddy proxies to it) |
| 7881 | LiveKit RTC over TCP (fallback) |
| 7882 | LiveKit RTC over UDP (where audio actually flows) |
| 7883 | Token service (loopback) |

## License

ISC, same as [announcer](https://github.com/dawsontoth/announcer).

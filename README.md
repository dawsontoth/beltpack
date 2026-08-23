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

## Icons

Every icon comes from one source, `appicon-raw.png`:

```bash
make icons
```

The generated sets are committed because they are build inputs, but they are
never edited by hand — change the source and regenerate. The script refuses a
source with an alpha channel, because iOS accepts one at build time and rejects
it at upload time, which is a bad place to find out.

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

## The management page

The tension between a native app and a command line resolves once you notice
that only one part is actually constrained: **audio capture has to happen in a
native process with a microphone grant, and everything else is just state an
operator wants to see and change.**

So the host is a background app bundle — `LSUIElement`, a menu bar item, no
window — that serves a management page on the comms VLAN:

```bash
make mac       # build and launch the host
make admin     # open the page
```

Status, device re-patching, who is on comms with live mute and speaking state,
start/stop, and pairing codes. Because it is a web page, you drive the booth Mac
from a phone at the back of the room rather than from its keyboard — which is
what makes pairing practical: pull it up, hold it out, the volunteer scans it.

Being an app bundle is not cosmetic. A bundle carries its own TCC identity, so
the microphone prompt is attributed to Beltpack. A bare CLI binary has none and
its prompt lands on whatever terminal launched it, which is exactly why the
prompt never appeared during setup.

The management passcode is deliberately separate from the join passcode:
the join one is printed on QR codes and handed round, while this one can
re-patch what the console is capturing. `setup.sh` generates both.

The CLI bridge stays for scripting and CI. It keeps its own room rather than
sharing the app's controller — that type is `@MainActor`, and a command-line
process has no app run loop.

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

## The watch

A camera operator has both hands on a camera. Reaching for a pocketed phone to
press talk is the friction the watch removes: the whole screen is the button,
pressed without looking, with a haptic on start and stop.

It is a **remote control, not a second client**. The phone owns the LiveKit
connection and the audio session, and the earbuds are paired to *it* — a watch
that joined the room independently would fight for the Bluetooth route and could
drag the earbuds into hands-free mode behind the phone's back. So the watch
sends intent and renders state it is told; it never decides whether it is
transmitting. A wrist that shows "talking" because a button was pressed, when
the phone never opened the mic, is worse than one that shows nothing.

It mirrors the phone's talk modes exactly, and the control is inert in
listen-only or open-mic, where a button would mean nothing.

`WCSession.sendMessage` only works while the phone app is reachable. That case
is shown rather than swallowed — the watch says "Open Beltpack on your phone"
instead of accepting a press that goes nowhere.

The watch app ships embedded in the phone app, so installing the phone app
carries it across. Its bundle identifier has to be the phone's with
`.watchkitapp` appended; XcodeGen's prefix rule would otherwise name it
`org.beltpack.BeltpackWatch`, which looks reasonable and stops the phone app
installing at all.

## Spoken announcements

Preset buttons speak a short cue over comms and show its text on every phone in
the room. Free text is there underneath for anything the presets do not cover.

Two paths for one event, deliberately. The speech rides the sender's existing
microphone track; the text goes over the room's data channel. Somebody in
listen-only, or with one earbud in a loud room, still needs to see that a cue
went out even though they will not hear it.

Getting speech onto the wire took a detour worth knowing about: WebRTC captures
from the device microphone, not from an arbitrary buffer, so there is no
"publish this audio" call. What there is, is the capture post-processing hook —
the same one the gain trim uses. An announcement is rendered to buffers up
front, then written over the microphone's samples while it plays. It takes the
buffer over rather than mixing into it, because mixing would put room noise and
whoever is nearby underneath a cue meant to be unambiguous.

Announcements need `canPublishData` on the join token. Without it the SFU drops
the message while the sending client reports success — the feature fails
invisibly, which is how it failed here first.

Banners clear themselves after twenty seconds. A cue from ten minutes ago stops
being information and becomes furniture.

## Personal levels

Each beltpack carries its own trims, because one position always wants the
director louder and one always sits too close to their own mic:

* **You hear** — applied per remote track, and to any that arrive later, so
  turning things down does not get undone by somebody joining.
* **They hear you** — applied in WebRTC's capture *post*-processing hook, which
  is deliberate: it runs after echo cancellation and noise suppression, so
  turning yourself up does not also turn up what those were trying to remove.

Both are capped at +6 dB rather than the SDK's +20. Past a modest boost you are
amplifying room noise, and on comms that is everyone's problem rather than only
your own.

The meters read from the same audio hooks, on a dBFS scale rather than a linear
one: a linear peak meter reads nearly full on ordinary speech and tells you
nothing. Green to about -12, amber to -3, red above. The send meter dims while
you are muted, since a meter that moves when nobody can hear you is worse than
no meter at all.

## The mute tone

iOS plays a tone each time the microphone mutes and unmutes, which on
push-to-talk means a beep on every press. That comes from the SDK's default
mute mode; **Settings > Mute tone** switches to the silent one, which also
avoids reconfiguring the audio engine on each toggle. The visible trade is that
the orange microphone indicator stays lit while you are on comms — arguably
more honest, since the mic really is armed and waiting. Silent is the default.

## Reconnection

LiveKit's own client reconnection handles short outages by itself, including
republishing. What it does not handle is an outage long enough for it to give
up — a console reboot, a server restart during setup, a long roam. Past that
point every client retries on its own with backoff capped at 15s, stopping as
soon as somebody deliberately leaves.

Both layers are exercised: a ~15s outage recovers inside the SDK, and an ~85s
one recovers through the retry loop after the SDK has given up.

The subtle failure is not the connection but the microphone. A publication does
not survive a drop, so a client that reconnects without re-arming comes back
able to listen and silently unable to talk — the button looks fine and nothing
reaches the console. Both clients clear the stale publication on disconnect so
arming runs again.

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
| 7884 | Management page |

## License

ISC, same as [announcer](https://github.com/dawsontoth/announcer).

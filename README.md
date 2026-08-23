# beltpack

Turns a phone and whatever earbuds are already in someone's pocket into a comms
position, alongside the wired Hollyland ring rather than instead of it.

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
* **Bus 2 — Comms → Phones** is a *mix-minus* feed: identical to Bus 1 except it
  must never contain the phone talk return, or phone users hear themselves a
  quarter-second late and it is unusable.
* Both buses ride the one USB cable already connecting the Mac to the WING.

---

# Setting up the booth Mac

Everything below is the whole job, in order. It takes about fifteen minutes, and
you can do all of it before the WING is involved.

## 1. Install the tools

```bash
brew install livekit livekit-cli
```

Xcode is needed only for the phone app. The Mac side builds with the Swift
toolchain that comes with the Command Line Tools.

## 2. Configure

```bash
./scripts/setup.sh --lan
```

Run it as many times as you like — it is idempotent, reports what it did and
what it skipped, and never replaces a secret it finds. On the first run it:

* installs anything missing from Homebrew,
* generates the LiveKit API key and secret,
* generates a **join passcode** (what volunteers use) and a **management
  passcode** (what you use — it can re-patch the console, so it is separate),
* detects this Mac's LAN address and writes `.env`,
* starts LiveKit briefly and checks its health endpoint.

Anything it cannot do itself becomes a numbered item at the end rather than a
silent omission. **Write the two passcodes down when it prints them.**

Use `--production` instead of `--lan` when you put Caddy in front and go back to
loopback. `--dev` is for a laptop with no phones involved.

## 3. Grant microphone access

```bash
make devices
```

Capturing the console counts as microphone access under macOS. Run this from
**Terminal.app**, approve the prompt, and confirm the device names appear. If
they come back blank:

```
Core Audio inputs (1):
  <no name — grant Microphone permission>  [id: ]
```

…that is macOS withholding them until permission is granted, not missing
hardware.

Note the channel count. **The WING reports 48 in**; anything else on a Mac
reports 1 or 2, which is how you spot it at a glance. Put its name in `.env` as
`BELTPACK_INPUT_DEVICE`. Any microphone will do for a trial run.

## 4. Build and start

```bash
make mac     # builds the host app
make up      # starts LiveKit, the token service and the host app
```

`make up` prints where everything is:

```
LiveKit:  OK
Token:    ok
Control:  http://127.0.0.1:7884/
Phones:   http://172.16.1.41:7883
```

`make down` stops it all. `make logs` follows the logs.

## 5. Open the control panel

```bash
make admin
```

Sign in with the management passcode. From there you can pick the console input
and return output, watch who is on comms with live mute and speaking state,
start and stop the bridge, and show pairing codes.

Because it is a web page on the comms network, you can drive the booth Mac from
a phone at the back of the room instead of from its keyboard — which is what
makes pairing practical.

## 6. Add a phone

Never type an address or a passcode. Show a code instead:

```bash
make pair            # iPhone: opens the app
make pair -- --web   # Android and laptops: opens the web client
```

The control panel has the same thing behind its **Pair** button, and any phone
already on comms can pair another from **Settings → Pair another phone**. That
last one is usually the easiest: hold your phone out to whoever just arrived.

The scanned phone still needs its own position name — "Camera 2", "FOH" — since
that is what everyone else sees.

> The passcode travels inside the code. A printed one is a key: anyone who
> photographs it is on comms.

---

# Configuration

`.env` is gitignored and holds every secret. `setup.sh` writes it; these are the
values worth knowing.

| Key | What it is |
|---|---|
| `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` | Generated. Never committed. |
| `BELTPACK_PASSCODE` | What volunteers enter, and what rides in a pairing code. |
| `BELTPACK_ADMIN_PASSCODE` | Gates the control panel. Deliberately not the same. |
| `BELTPACK_INPUT_DEVICE` | Substring of the Core Audio input name, e.g. `WING`. |
| `BELTPACK_OUTPUT_DEVICE` | Where phone audio returns. Only used with `BELTPACK_SUBSCRIBE`. |
| `BELTPACK_NODE_IP` | This Mac's LAN address. Phones send media straight here. |
| `BELTPACK_CLIENT_URL` | What a phone is pointed at. Used to build pairing codes. |
| `BELTPACK_CAN_PUBLISH` | Whether phones may talk. |
| `BELTPACK_SUBSCRIBE` | Whether the bridge returns phone audio to the console. |

`BELTPACK_NODE_IP` is the one that bites. Phones connect their **media** straight
to that address, bypassing everything else. Get it wrong and signalling connects
perfectly, the app says "On comms", and no audio ever arrives.

Nothing secret belongs in `deploy/livekit.yaml` — it is committed to a public
repo. Keys and the LAN address are injected by `deploy/run.sh` from `.env`.

| Port | Service |
|---|---|
| 7880 | LiveKit signalling |
| 7881 | LiveKit RTC over TCP (fallback) |
| 7882 | LiveKit RTC over UDP (where audio flows) |
| 7883 | Token service |
| 7884 | Control panel |

---

# Using it

## Talking

Four talk modes per phone: listen only, hold to talk, tap to latch, or open mic.
Push-to-talk is the default, because ten open mics in a sanctuary is a different
kind of problem.

The microphone is armed when you join, not when you first press. The track is
published already muted, so a press is a local unmute rather than an audio
session switch, a track creation and a publish negotiation. That matters because
the session switch is what drags Bluetooth from A2DP to hands-free, which takes
well over a second on real earbuds.

**Settings → Microphone** lists the real input ports, and can be set to **Off** —
a phone that listens and can never talk. Choosing a Bluetooth port is what puts
the link into hands-free mode and drops both directions to 16 kHz; choosing the
phone's own microphone keeps the earbuds in high quality but means talking into
the handset. That is one decision, so it is one setting.

**Settings → Speaker** can be set to **Silent**: a position that sees cues
without ever adding sound to the room. iOS will not let an app refuse an output,
so silence is done by muting the incoming tracks — same result, reachable where a
route is not.

## Levels

Each beltpack carries its own trims. **You hear** is applied per remote track and
re-applied to tracks that arrive later, so turning things down is not undone by
somebody joining. **They hear you** runs in the capture post-processing hook,
after echo cancellation and noise suppression, so turning yourself up does not
turn up what those were removing. Both cap at +6 dB.

Meters are RMS on a dBFS scale — green to about −12, amber to −3, red above. A
linear peak meter reads nearly full on ordinary speech and tells you nothing.

## Announcements

Preset buttons speak a short cue over comms and show its text on every other
phone as a notification. Free text covers what the presets do not, and the
buttons are editable in **Settings → Announcement buttons**.

Two paths for one event: the speech rides the sender's microphone track, the text
goes over the data channel. Somebody in listen-only, or with one earbud in a loud
room, still needs to see a cue went out.

## The watch

A watchOS app puts talk on the wrist, for an operator with both hands on a
camera. It is a remote control, not a second client — the phone owns the audio
session and the earbuds are paired to it, so a watch that joined independently
would fight for the Bluetooth route.

## Reconnection

LiveKit handles short outages itself. Past the point where it gives up — a
console reboot, a long roam — every client retries with backoff capped at 15s.
Both layers are exercised: a ~15s outage recovers inside the SDK, an ~85s one
through the retry loop.

The subtle failure is not the connection but the microphone: a publication does
not survive a drop, so a client that reconnects without re-arming comes back able
to listen and silently unable to talk.

---

# Deploying for real

## Run it unattended

```bash
make install-agents
for s in livekit token host; do
  launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/org.beltpack.$s.plist
done
```

These are **LaunchAgents, not LaunchDaemons**, and the host is an app bundle
rather than a bare binary. Both for the same reason: a bundle has its own TCC
identity, so the microphone prompt is attributed to Beltpack. A command-line
binary has none, and its prompt lands on whatever terminal started it. The Mac
needs auto-login for this to come back after a reboot.

Make the Mac behave like an appliance:

```bash
sudo pmset -a sleep 0 disablesleep 1
sudo pmset -a autorestart 1
```

Turn off automatic macOS updates. A restart at 3 a.m. Sunday is exactly the
failure nobody thinks to check for.

## TLS

Browsers refuse WebRTC and service workers outside a secure context, and a bare
LAN IP is not one. Point a real hostname's A record at the Mac's private address
and let Caddy get a Let's Encrypt certificate over a DNS-01 challenge — see
`deploy/Caddyfile`. Homebrew's Caddy has no DNS plugins compiled in, so this
needs `xcaddy build --with github.com/caddy-dns/<provider>`.

Then switch `setup.sh` to `--production`, which puts the services back on
loopback behind Caddy.

## Wi-Fi

Dedicated 5 GHz SSID on its own VLAN. Disable legacy low data rates, leave WMM
on, and enable 802.11r/k/v if there is more than one AP — camera ops roam, and an
unassisted roam is a two-second dropout.

Client isolation is fine: every stream goes phone-to-server, never phone-to-phone.
No multicast anywhere, which is exactly why this is WebRTC and not AES67 or Dante
to the handsets.

---

# When something is wrong

**No microphone prompt, or device names are blank.** Enumerating devices never
triggers the prompt; only asking for access does. `make devices` asks. Run it
from Terminal.app — an editor or an agent has no way to show you the dialog.

**"On comms" but no audio.** Check `BELTPACK_NODE_IP` is this Mac's address on
the network the phones are on. Signalling goes through the token service; media
does not.

**A device that advertises a valid format and then fails.** Some virtual devices
(ZoomAudioDevice is one) report 48 kHz and the right channel count, then kill the
process when AVAudioEngine opens them:

```
*** Terminating app due to uncaught exception 'com.apple.coreaudio.avfaudio',
    reason: 'Input HW format is invalid'
```

Real class-compliant hardware is fine. The last `beltpack-bridge:` line in the
log names the device that did it.

**Core Audio wedged.** Repeatedly killing processes that hold audio devices can
leave `coreaudiod` stuck: captures stall for 30 seconds and fail. `sudo killall
coreaudiod` clears it.

**Nothing in the logs.** The host app is a bundle and has nowhere to print, so it
logs to the unified log: `make mac-logs`.

**A phone will not install.** Changing signing team blocks an upgrade with a
mismatched-application-identifier error; the app has to be deleted from the phone
first.

---

# Layout

| Path | What it is |
|---|---|
| `server/` | Swift package. `BeltpackKit` holds the shared logic; `BeltpackBridge` is the headless CLI. |
| `mac/` | The host app: audio bridge, menu bar item, and the control panel. |
| `ios/` | iPhone and watch apps, generated by XcodeGen from `ios/project.yml`. |
| `web/` | PWA for Android and booth laptops. |
| `token/` | Zero-dependency Node service. Trades a passcode for a short-lived token. |
| `deploy/` | LiveKit config, Caddyfile, LaunchAgents, and the console runbook. |
| `scripts/` | Setup, start, stop, and icon generation. |

`make check` builds everything and runs every test. `make icons` regenerates all
app icons from `appicon-raw.png`.

The iOS app needs `ios/Local.xcconfig` with your `DEVELOPMENT_TEAM`; `make ios`
creates it from the example on first use. That file and `.env` are gitignored and
must stay that way — this repo is public.

# Status

Verified end to end on real hardware: console to phone and back, push-to-talk,
spoken announcements, announcement text across clients, pairing by deep link,
personal levels, and reconnection at both layers.

Not yet exercised: the WING itself over USB, the mix-minus routing that depends
on it, TLS via Caddy, the LaunchAgents, and TestFlight distribution.

# What this is not

An in-ear monitor system. Expect roughly 130 ms to wired earbuds and 250 ms to
AirPods. Fine for cues and talkback; nowhere near good enough for a musician
monitoring themselves.

# License

ISC, same as [announcer](https://github.com/dawsontoth/announcer).

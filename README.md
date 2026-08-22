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

Phase 1 is listen-only. Phase 2 adds push-to-talk, summed back into a single
WING input channel that routes to Bus 1 **only**.

## Layout

| Path | What it is |
|---|---|
| `server/` | Swift. Publishes a WING console bus into a LiveKit room as Opus. |
| `ios/` | Swift + XcodeGen. The native app, because iOS Safari suspends WebRTC on lock. |
| `web/` | PWA for Android and booth laptops, where background audio already works. |
| `token/` | Zero-dependency Node service. Trades a passcode for a short-lived token. |
| `deploy/` | LiveKit config, Caddyfile, LaunchAgents, and the console runbook. |

## Quickstart

```bash
cp .env.example .env          # then fill it in
make devices                  # find the WING's Core Audio name
make build                    # bridge + PWA
make run-livekit              # in one terminal
make run-token                # in another
make run-bridge               # in a third
make ios                      # opens Xcode
```

`make check` builds everything and lints what can be linted.

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

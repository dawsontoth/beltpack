# Runbook

## 1. WING routing

Build two buses:

| | Bus 1 · Comms Mix | Bus 2 · Comms → Phones |
|---|---|---|
| Announcer Pi | yes | yes |
| Stage talkback | yes | yes |
| Board talkback | yes | yes |
| Wired headset mics | yes | yes |
| Phone talk return (phase 2) | yes | **never** |
| Routes to | Hollyland base | Mac, over USB |

The "never" is the whole design. Phone audio comes back a quarter-second late;
if Bus 2 contains it, phone users hear themselves delayed.

Phone-to-phone is handled separately and for free — an SFU never sends a
participant their own track — so you only have to get the console half right.

## 2. Picking the right channels

The WING presents as one 48-in/48-out device and WebRTC captures its *first*
channels. To send a specific bus, open **Audio MIDI Setup**, create an
**Aggregate Device** exposing only the WING channel pair carrying Bus 2, and
point `BELTPACK_INPUT_DEVICE` at the aggregate's name instead of "WING".

Confirm with `make devices`. If names come back empty, grant Microphone
permission first — see the root README.

## 3. Making the Mac behave like an appliance

```bash
sudo pmset -a sleep 0 disablesleep 1   # never sleep
sudo pmset -a autorestart 1            # come back after a power cut
```

Enable auto-login (the LaunchAgents need a session), and turn **off** automatic
macOS updates. A restart at 3 a.m. Sunday is exactly the failure nobody thinks
to check for.

## 4. Install the services

```bash
make server            # build the release binary first
make install-agents
for s in livekit token bridge; do
  launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/org.beltpack.$s.plist
done
make logs
```

## 5. Wi-Fi

Dedicated 5 GHz SSID on its own VLAN. Disable legacy low data rates, leave WMM
on, and enable 802.11r/k/v if there is more than one AP — camera ops roam, and
an unassisted roam is a two-second dropout.

Client isolation is fine: every stream goes phone-to-server, never
phone-to-phone. Just keep client-to-server reachable.

No multicast anywhere. That is exactly why this is WebRTC and not AES67 or
Dante to the handsets — multicast AoIP does not survive Wi-Fi.

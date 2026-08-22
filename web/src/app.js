// Beltpack web client.
//
// Android Chrome keeps WebRTC audio running when the tab is backgrounded, which
// is the entire reason this is a web app while iOS gets a native one. Do not
// assume the same behaviour if you ever point an iPhone at this page.

import { Room, RoomEvent } from "livekit-client";

import { normalize } from "./server-address.js";

const SETTINGS_KEY = "beltpack.settings";

const els = {
  dial: document.querySelector("#dial"),
  status: document.querySelector("#status"),
  detail: document.querySelector("#detail"),
  join: document.querySelector("#join"),
  talk: document.querySelector("#talk"),
  talkCaption: document.querySelector("#talk-caption"),
  talkWrap: document.querySelector("#talk-wrap"),
  talkMode: document.querySelector("#talkMode"),
  form: document.querySelector("#settings"),
  server: document.querySelector("#server"),
  resolved: document.querySelector("#resolved"),
  identity: document.querySelector("#identity"),
  passcode: document.querySelector("#passcode"),
};

const room = new Room({ adaptiveStream: false, dynacast: false });
let connected = false;
let talking = false;
let armed = false;
/** Set while the user means to be on comms. A drop is only worth retrying if
 *  nobody pressed Leave. */
let shouldBeConnected = false;
let reconnectTimer = null;
let reconnectDelay = 1000;
let micError = null;

const NEEDS_MIC = (mode) => mode !== "listenOnly";

function loadSettings() {
  try {
    return JSON.parse(localStorage.getItem(SETTINGS_KEY)) ?? {};
  } catch {
    return {};
  }
}

function currentSettings() {
  return {
    server: els.server.value.trim(),
    identity: els.identity.value.trim(),
    passcode: els.passcode.value,
    talkMode: els.talkMode.value,
  };
}

function saveSettings() {
  localStorage.setItem(SETTINGS_KEY, JSON.stringify(currentSettings()));
}

/** Derived from room state rather than assumed, because the console is
 *  normally already in the room when a beltpack joins and TrackSubscribed can
 *  fire before or after connect() returns. */
function describeRoom() {
  const remotes = [...room.remoteParticipants.values()];
  const consoleLive = remotes.some((p) =>
    [...p.audioTrackPublications.values()].some((pub) => pub.isSubscribed),
  );
  if (!consoleLive) return "Waiting for the console";
  const others = remotes.length - 1;
  if (others <= 0) return "Console live";
  return `Console live \u00B7 ${others} other position${others === 1 ? "" : "s"}`;
}

function setState(state, status, detail = "") {
  els.dial.dataset.state = talking ? "talking" : state;
  els.status.textContent = talking ? "Talking" : status;
  els.detail.textContent = detail;
  els.join.textContent = connected ? "Leave comms" : "Join comms";
  els.join.dataset.connected = String(connected);
  renderTalk();
}

/** Forgiving, but never silently: show what the typed address became. */
function renderResolved() {
  const raw = els.server.value.trim();
  if (!raw) {
    els.resolved.textContent = "An address or a name is enough — http, https and the port are worked out for you.";
    els.resolved.dataset.bad = "false";
    return;
  }
  const resolved = normalize(raw);
  els.resolved.textContent = resolved ? `Connects to ${resolved}` : "Can't make sense of that address.";
  els.resolved.dataset.bad = String(resolved === null);
}

function renderTalk() {
  const mode = els.talkMode.value;
  els.talkWrap.hidden = !connected || mode === "open" || !NEEDS_MIC(mode) || micError !== null;
  els.talk.dataset.talking = String(talking);
  els.talkCaption.textContent =
    mode === "pushToTalk"
      ? talking
        ? "Release to stop"
        : "Hold to talk"
      : talking
        ? "Tap to stop"
        : "Tap to talk";
}

async function fetchCredentials({ server, identity, passcode }) {
  const base = normalize(server);
  if (!base) throw new Error("Can't make sense of that server address.");

  const url = new URL("/token", base);
  url.searchParams.set("identity", identity);

  // The passcode rides in a header, never the query string.
  const response = await fetch(url, { headers: { "X-Beltpack-Passcode": passcode } });
  if (response.status === 401) throw new Error("That passcode was rejected.");
  if (!response.ok) throw new Error(`Comms server returned ${response.status}.`);
  return response.json();
}

async function join() {
  const settings = currentSettings();
  if (!settings.server || !settings.identity || !settings.passcode) {
    setState("failed", "Missing details", "Fill in the server, your name, and the passcode.");
    return;
  }

  saveSettings();
  shouldBeConnected = true;
  micError = null;
  setState("connecting", "Connecting…");

  try {
    const { url, token } = await fetchCredentials(settings);
    await room.connect(url, token);
    connected = true;
    reconnectDelay = 1000;
    setState("listening", "On comms", describeRoom());

    // Arm now, not on the first press. The first setMicrophoneEnabled has to
    // run getUserMedia and negotiate a publish; every later one is just a
    // mute, because stopMicTrackOnMute defaults to false.
    if (NEEDS_MIC(settings.talkMode)) await armMicrophone();
    if (settings.talkMode === "open") await startTalking();
  } catch (error) {
    connected = false;
    // A failed fetch on a LAN almost always means the wrong Wi-Fi.
    const message =
      error instanceof TypeError
        ? "Can't reach the comms server. Check you're on the comms Wi-Fi."
        : error.message;

    if (shouldBeConnected) {
      scheduleReconnect(message);
    } else {
      setState("failed", "Not connected", message);
    }
  }
}

/** Retries with backoff. An access-point roam, a server restart, or a laptop
 *  waking all drop the room; without this the client sits on "Not connected"
 *  until somebody notices and taps Join. */
function scheduleReconnect(reason) {
  if (!shouldBeConnected || reconnectTimer) return;

  connected = false;
  setState("connecting", "Reconnecting…", reason ?? "");

  reconnectTimer = setTimeout(async () => {
    reconnectTimer = null;
    if (!shouldBeConnected) return;
    reconnectDelay = Math.min(reconnectDelay * 2, 15000);
    await join();
  }, reconnectDelay);
}

function cancelReconnect() {
  if (reconnectTimer) clearTimeout(reconnectTimer);
  reconnectTimer = null;
  reconnectDelay = 1000;
}

async function leave() {
  shouldBeConnected = false;
  cancelReconnect();
  await disarmMicrophone();
  await room.disconnect();
  connected = false;
  clearAudioSinks();
  setState("idle", "Not connected");
}

/** Remote audio elements outlive a dropped connection otherwise, leaving a
 *  dead <audio> per outage. */
function clearAudioSinks() {
  document.querySelectorAll("#sinks audio").forEach((el) => el.remove());
}

async function armMicrophone() {
  if (armed) return;
  try {
    // A voice in a loud room, unlike the console feed: leave the browser's
    // echo cancellation and noise suppression switched on.
    await room.localParticipant.setMicrophoneEnabled(true, {
      echoCancellation: true,
      noiseSuppression: true,
      autoGainControl: true,
    });
    await room.localParticipant.setMicrophoneEnabled(false);
    armed = true;
  } catch (error) {
    // Not being able to talk is not the same as not being on comms. Someone
    // with a denied or missing microphone should still hear the console
    // rather than be told the connection failed.
    armed = false;
    micError = error.message;
    setState("listening", "On comms", `Listening only — microphone unavailable (${error.message})`);
  }
}

async function disarmMicrophone() {
  if (!armed) return;
  armed = false;
  talking = false;
  try {
    await room.localParticipant.setMicrophoneEnabled(false);
  } catch {
    // Leaving the room takes the track with it either way.
  }
}

async function startTalking() {
  if (!connected || talking) return;
  if (!armed) await armMicrophone();
  if (!armed) return;
  const started = performance.now();
  try {
    await room.localParticipant.setMicrophoneEnabled(true);
    talking = true;
    console.info(`beltpack: talk started in ${Math.round(performance.now() - started)}ms`);
    setState("listening", "On comms");
  } catch (error) {
    setState("failed", "Microphone blocked", error.message);
  }
}

async function stopTalking() {
  if (!talking) return;
  talking = false;
  try {
    await room.localParticipant.setMicrophoneEnabled(false);
  } finally {
    setState(connected ? "listening" : "idle", connected ? "On comms" : "Not connected");
  }
}

room.on(RoomEvent.Reconnecting, () => setState("connecting", "Reconnecting…"));
room.on(RoomEvent.Reconnected, () => setState("listening", "On comms"));
room.on(RoomEvent.Disconnected, () => {
  connected = false;
  talking = false;
  armed = false;
  clearAudioSinks();
  if (shouldBeConnected) scheduleReconnect("Connection lost");
  else setState("idle", "Not connected");
});

// An audio element per remote track. Browsers will not start these without a
// user gesture, which the join button provides.
room.on(RoomEvent.TrackSubscribed, (track) => {
  if (track.kind !== "audio") return;
  const element = track.attach();
  element.autoplay = true;
  document.querySelector("#sinks").append(element);
  setState("listening", "On comms", describeRoom());
});

room.on(RoomEvent.TrackUnsubscribed, (track) => {
  track.detach().forEach((el) => el.remove());
  if (connected) setState("listening", "On comms", describeRoom());
});

for (const event of [RoomEvent.ParticipantConnected, RoomEvent.ParticipantDisconnected]) {
  room.on(event, () => {
    if (connected) setState("listening", "On comms", describeRoom());
  });
}

els.join.addEventListener("click", () => (connected ? leave() : join()));
els.form.addEventListener("submit", (event) => {
  event.preventDefault();
  saveSettings();
});
els.server.addEventListener("input", renderResolved);
els.talkMode.addEventListener("change", async () => {
  saveSettings();
  const mode = els.talkMode.value;
  if (connected) {
    if (!NEEDS_MIC(mode)) await disarmMicrophone();
    else {
      await armMicrophone();
      if (mode === "open") await startTalking();
      else if (talking) await stopTalking();
    }
  }
  renderTalk();
});

// Pointer events rather than click, so hold-to-talk works on touch and mouse
// alike and releases even if the finger slides off the button.
els.talk.addEventListener("pointerdown", (event) => {
  event.preventDefault();
  els.talk.setPointerCapture(event.pointerId);
  if (els.talkMode.value === "pushToTalk") startTalking();
});
els.talk.addEventListener("pointerup", () => {
  if (els.talkMode.value === "pushToTalk") stopTalking();
  else if (els.talkMode.value === "latch") (talking ? stopTalking() : startTalking());
});
els.talk.addEventListener("pointercancel", () => {
  if (els.talkMode.value === "pushToTalk") stopTalking();
});

/** Applies a scanned pairing link, then scrubs it from the address bar so the
 *  passcode does not sit in history or get shared with a screenshot. Applied
 *  whole or not at all, matching PairingLink on the native side. */
function applyPairingLink() {
  const params = new URLSearchParams(location.search);
  const server = params.get("server");
  const passcode = params.get("passcode");
  if (!server || !passcode) return false;

  els.server.value = server;
  els.passcode.value = passcode;
  const identity = params.get("identity");
  if (identity) els.identity.value = identity;
  saveSettings();

  history.replaceState(null, "", location.pathname);
  return true;
}

const saved = loadSettings();
els.server.value = saved.server ?? "";
els.identity.value = saved.identity ?? "";
els.passcode.value = saved.passcode ?? "";
els.talkMode.value = saved.talkMode ?? "pushToTalk";

const paired = applyPairingLink();
renderResolved();
setState("idle", "Not connected");

if (paired) {
  // A scanned code should not also require finding the join button, but the
  // name is still needed and browsers want a gesture before playing audio.
  setState(
    "idle",
    els.identity.value ? "Paired — tap to join" : "Paired — add your position",
    "Server and passcode came from the code you scanned.",
  );
}

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("./sw.js").catch(() => {
    // Offline caching is a nicety; the app works without it.
  });
}

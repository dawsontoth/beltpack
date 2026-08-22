// Beltpack web client.
//
// Android Chrome keeps WebRTC audio running when the tab is backgrounded, which
// is the entire reason this is a web app while iOS gets a native one. Do not
// assume the same behaviour if you ever point an iPhone at this page.

import { Room, RoomEvent } from "livekit-client";

const SETTINGS_KEY = "beltpack.settings";

const els = {
  dial: document.querySelector("#dial"),
  status: document.querySelector("#status"),
  detail: document.querySelector("#detail"),
  join: document.querySelector("#join"),
  form: document.querySelector("#settings"),
  server: document.querySelector("#server"),
  identity: document.querySelector("#identity"),
  passcode: document.querySelector("#passcode"),
};

const room = new Room({ adaptiveStream: false, dynacast: false });
let connected = false;

function loadSettings() {
  try {
    return JSON.parse(localStorage.getItem(SETTINGS_KEY)) ?? {};
  } catch {
    return {};
  }
}

function saveSettings() {
  localStorage.setItem(
    SETTINGS_KEY,
    JSON.stringify({
      server: els.server.value.trim(),
      identity: els.identity.value.trim(),
      passcode: els.passcode.value,
    }),
  );
}

function setState(state, status, detail = "") {
  els.dial.dataset.state = state;
  els.status.textContent = status;
  els.detail.textContent = detail;
  els.join.textContent = connected ? "Leave comms" : "Join comms";
  els.join.dataset.connected = String(connected);
}

async function fetchCredentials({ server, identity, passcode }) {
  const url = new URL("/token", server);
  url.searchParams.set("identity", identity);

  const response = await fetch(url, {
    // The passcode rides in a header, never the query string.
    headers: { "X-Beltpack-Passcode": passcode },
  });

  if (response.status === 401) throw new Error("That passcode was rejected.");
  if (!response.ok) throw new Error(`Comms server returned ${response.status}.`);
  return response.json();
}

async function join() {
  const settings = {
    server: els.server.value.trim(),
    identity: els.identity.value.trim(),
    passcode: els.passcode.value,
  };

  if (!settings.server || !settings.identity || !settings.passcode) {
    setState("failed", "Missing details", "Fill in the server, your name, and the passcode.");
    return;
  }

  saveSettings();
  setState("connecting", "Connecting…");

  try {
    const { url, token } = await fetchCredentials(settings);
    await room.connect(url, token);
    connected = true;
    setState("listening", "On comms", "Waiting for the console");
  } catch (error) {
    connected = false;
    // A failed fetch on a LAN almost always means the wrong Wi-Fi.
    const message =
      error instanceof TypeError
        ? "Can't reach the comms server. Check you're on the comms Wi-Fi."
        : error.message;
    setState("failed", "Not connected", message);
  }
}

async function leave() {
  await room.disconnect();
  connected = false;
  setState("idle", "Not connected");
}

room.on(RoomEvent.Reconnecting, () => setState("connecting", "Reconnecting…"));
room.on(RoomEvent.Reconnected, () => setState("listening", "On comms"));
room.on(RoomEvent.Disconnected, () => {
  connected = false;
  setState("idle", "Not connected");
});

// An audio element per remote track. Browsers will not start these without a
// user gesture, which the join button provides.
room.on(RoomEvent.TrackSubscribed, (track) => {
  if (track.kind !== "audio") return;
  const element = track.attach();
  element.autoplay = true;
  document.querySelector("#sinks").append(element);
  setState("listening", "On comms", `${room.remoteParticipants.size} position(s) on air`);
});

room.on(RoomEvent.TrackUnsubscribed, (track) => track.detach().forEach((el) => el.remove()));

els.join.addEventListener("click", () => (connected ? leave() : join()));
els.form.addEventListener("submit", (event) => {
  event.preventDefault();
  saveSettings();
});

// Restore what this volunteer set last time.
const saved = loadSettings();
els.server.value = saved.server ?? "";
els.identity.value = saved.identity ?? "";
els.passcode.value = saved.passcode ?? "";
setState("idle", "Not connected");

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("./sw.js").catch(() => {
    // Offline caching is a nicety; the app works without it.
  });
}

#!/usr/bin/env node
// Beltpack token service.
//
// Trades a shared passcode for a short-lived LiveKit access token, so no
// client ever holds the API secret. Zero dependencies on purpose: this runs
// unattended on the booth Mac, and every dependency is another thing that can
// need updating at the wrong moment.

import { createHmac, timingSafeEqual } from "node:crypto";
import { createServer } from "node:http";

const {
  LIVEKIT_API_KEY,
  LIVEKIT_API_SECRET,
  BELTPACK_ROOM = "comms",
  BELTPACK_PASSCODE,
  // What clients should connect to. Usually the public wss:// address Caddy
  // terminates, not the loopback address LiveKit itself binds.
  BELTPACK_PUBLIC_URL = "ws://127.0.0.1:7880",
  TOKEN_PORT = "7883",
  // Loopback by default because Caddy fronts this in production. A LAN test
  // with no TLS needs 0.0.0.0 so a phone can reach it.
  TOKEN_BIND = "127.0.0.1",
  // Phase 2: flip to "true" to let beltpacks publish push-to-talk audio.
  BELTPACK_CAN_PUBLISH = "false",
} = process.env;

for (const [key, value] of Object.entries({ LIVEKIT_API_KEY, LIVEKIT_API_SECRET, BELTPACK_PASSCODE })) {
  if (!value) {
    console.error(`token: set ${key}. Copy .env.example to .env and fill it in.`);
    process.exit(1);
  }
}

if (LIVEKIT_API_SECRET.length < 32) {
  console.error("token: LIVEKIT_API_SECRET must be at least 32 characters.");
  process.exit(1);
}

const base64url = (input) =>
  Buffer.from(input).toString("base64").replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");

function mint(identity) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "HS256", typ: "JWT" };
  const payload = {
    iss: LIVEKIT_API_KEY,
    sub: identity,
    name: identity,
    nbf: now,
    exp: now + 12 * 60 * 60, // outlasts any service
    video: {
      room: BELTPACK_ROOM,
      roomJoin: true,
      canPublish: BELTPACK_CAN_PUBLISH === "true",
      canSubscribe: true,
      // Required for announcements: the text of a spoken cue travels on the
      // data channel. Without it the SFU silently drops the message while the
      // sending client reports success, so the feature fails invisibly.
      canPublishData: true,
    },
  };

  const signingInput = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;
  const signature = createHmac("sha256", LIVEKIT_API_SECRET).update(signingInput).digest();
  return `${signingInput}.${base64url(signature)}`;
}

/** Constant-time compare so the passcode can't be guessed by timing. */
function passcodeMatches(supplied) {
  const a = Buffer.from(String(supplied ?? ""));
  const b = Buffer.from(BELTPACK_PASSCODE);
  return a.length === b.length && timingSafeEqual(a, b);
}

/** Passcode-gated on a private VLAN, so any origin is acceptable. Without
 *  this a page served from a different port than the token service — any
 *  setup that is not Caddy fronting both — fails with an opaque network
 *  error that looks like a Wi-Fi problem. */
function applyCORS(res) {
  res.setHeader("access-control-allow-origin", "*");
  res.setHeader("access-control-allow-methods", "GET, OPTIONS");
  res.setHeader("access-control-allow-headers", "X-Beltpack-Passcode");
  res.setHeader("access-control-max-age", "86400");
}

const server = createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  applyCORS(res);

  // The custom passcode header makes every request preflighted.
  if (req.method === "OPTIONS") {
    res.writeHead(204).end();
    return;
  }

  if (url.pathname === "/healthz") {
    res.writeHead(200, { "content-type": "text/plain" }).end("ok\n");
    return;
  }

  if (url.pathname !== "/token") {
    res.writeHead(404).end();
    return;
  }

  if (!passcodeMatches(req.headers["x-beltpack-passcode"])) {
    res.writeHead(401, { "content-type": "application/json" }).end(JSON.stringify({ error: "bad passcode" }));
    return;
  }

  const identity = (url.searchParams.get("identity") ?? "").trim().slice(0, 40);
  if (!identity) {
    res.writeHead(400, { "content-type": "application/json" }).end(JSON.stringify({ error: "identity required" }));
    return;
  }

  res
    .writeHead(200, { "content-type": "application/json", "cache-control": "no-store" })
    .end(JSON.stringify({ url: BELTPACK_PUBLIC_URL, token: mint(identity) }));

  console.log(`token: issued for "${identity}"`);
});

// Node binds 0.0.0.0 as IPv4 only, but browsers routinely resolve "localhost"
// to ::1 first and then fail with a connection refused that reads like the
// server is down. "::" binds both families.
const bindAddress = TOKEN_BIND === "0.0.0.0" ? "::" : TOKEN_BIND;

server.listen(Number(TOKEN_PORT), bindAddress, () => {
  console.log(`token: listening on ${bindAddress}:${TOKEN_PORT}, room "${BELTPACK_ROOM}"`);
});

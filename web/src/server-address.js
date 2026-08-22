// Turns what someone actually types into a usable server URL.
//
// Mirrors ios/Sources/ServerAddress.swift deliberately — the two clients must
// agree on what "192.168.1.50" means, or the same note taped to the wall gives
// different results depending on which phone you hold.
//
//   172.16.1.41            -> http://172.16.1.41:7883
//   comms.church.org       -> https://comms.church.org
//   HTTPS://Comms.Church.Org/  -> https://comms.church.org

export const DEFAULT_LOCAL_PORT = 7883;

/** Private, loopback, link-local or mDNS — anything that cannot have a public cert. */
export function isLocal(host) {
  if (host === "localhost" || host.endsWith(".local")) return true;

  const octets = host.split(".").map((part) => (/^\d+$/.test(part) ? Number(part) : NaN));
  if (octets.length !== 4 || octets.some((n) => !Number.isInteger(n) || n < 0 || n > 255)) {
    return false;
  }

  const [a, b] = octets;
  if (a === 10 || a === 127) return true;
  if (a === 192 && b === 168) return true;
  if (a === 169 && b === 254) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  return false;
}

/** @returns {string|null} a normalised absolute URL, or null if it makes no sense. */
export function normalize(raw) {
  let text = String(raw ?? "").trim();
  if (!text) return null;

  let scheme = null;
  const schemeAt = text.indexOf("://");
  if (schemeAt !== -1) {
    scheme = text.slice(0, schemeAt).toLowerCase();
    text = text.slice(schemeAt + 3);
  }

  // Drop any path pasted along with the host; we always talk to /token, and a
  // stray /token in the setting would double up.
  const slash = text.indexOf("/");
  if (slash !== -1) text = text.slice(0, slash);
  if (!text) return null;

  let host = text;
  let port = null;
  if (!text.startsWith("[")) {
    const colon = text.indexOf(":");
    if (colon !== -1) {
      const tail = text.slice(colon + 1);
      if (!/^\d+$/.test(tail)) return null;
      const parsed = Number(tail);
      if (parsed < 1 || parsed > 65535) return null;
      host = text.slice(0, colon);
      port = parsed;
    }
  }

  host = host.toLowerCase();
  if (!host || host.includes(" ")) return null;

  const local = isLocal(host);
  const resolvedScheme = scheme ?? (local ? "http" : "https");
  if (resolvedScheme !== "http" && resolvedScheme !== "https") return null;

  // Only default the port for a bench setup; a real hostname sits behind Caddy
  // on 443, where naming the port would be wrong.
  let suffix = "";
  if (port !== null) suffix = `:${port}`;
  else if (local && resolvedScheme === "http") suffix = `:${DEFAULT_LOCAL_PORT}`;

  return `${resolvedScheme}://${host}${suffix}`;
}

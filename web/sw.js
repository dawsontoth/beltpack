// Cache the shell so the app opens instantly and survives a flaky moment on
// the way to the booth. Tokens and media are never cached.
const CACHE = "beltpack-v2";
const SHELL = [
  "./",
  "./index.html",
  "./styles.css",
  "./dist/app.js",
  "./manifest.webmanifest",
  "./icon.svg",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/apple-touch-icon.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)));
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key)))),
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  const { request } = event;
  // Never serve a stale token, and never cache the signalling socket.
  if (request.method !== "GET" || new URL(request.url).pathname.startsWith("/token")) return;
  event.respondWith(caches.match(request).then((hit) => hit ?? fetch(request)));
});

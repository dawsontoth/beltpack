import assert from "node:assert/strict";
import { test } from "node:test";

import { normalize } from "../src/server-address.js";

// Kept in step with ios/Tests/ServerAddressTests.swift on purpose: the two
// clients must agree on what a given address means.

test("a bare private IP becomes http on the default port", () => {
  assert.equal(normalize("172.16.1.41"), "http://172.16.1.41:7883");
  assert.equal(normalize("192.168.0.10"), "http://192.168.0.10:7883");
  assert.equal(normalize("10.0.0.5"), "http://10.0.0.5:7883");
});

test("an explicit port is respected", () => {
  assert.equal(normalize("172.16.1.41:9000"), "http://172.16.1.41:9000");
});

test("a real hostname becomes https with no port", () => {
  assert.equal(normalize("comms.church.org"), "https://comms.church.org");
});

test("an explicit scheme always wins", () => {
  assert.equal(normalize("http://comms.church.org"), "http://comms.church.org");
  assert.equal(normalize("https://172.16.1.41"), "https://172.16.1.41");
});

test("whitespace, case and trailing slashes are forgiven", () => {
  assert.equal(normalize("  HTTPS://Comms.Church.Org/  "), "https://comms.church.org");
  assert.equal(normalize("172.16.1.41/"), "http://172.16.1.41:7883");
});

test("a pasted path is discarded so /token is not doubled up", () => {
  assert.equal(normalize("http://172.16.1.41:7883/token"), "http://172.16.1.41:7883");
});

test(".local and localhost count as local", () => {
  assert.equal(normalize("comms.local"), "http://comms.local:7883");
  assert.equal(normalize("localhost"), "http://localhost:7883");
});

test("public-looking IPs are not treated as local", () => {
  // 172.32 is just outside the private 172.16-31 range; a classic off-by-one.
  assert.equal(normalize("172.32.0.1"), "https://172.32.0.1");
  assert.equal(normalize("8.8.8.8"), "https://8.8.8.8");
});

test("nonsense is rejected rather than guessed at", () => {
  assert.equal(normalize(""), null);
  assert.equal(normalize("   "), null);
  assert.equal(normalize("172.16.1.41:notaport"), null);
  assert.equal(normalize("ftp://172.16.1.41"), null);
});

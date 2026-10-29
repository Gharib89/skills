// The joins measure's face bytes: a data: URL's own, whole.
import { test } from "node:test";
import assert from "node:assert/strict";
import { urlBytes } from "../../skills/creative-video/scripts/lib/backend/joins.mjs";

const origin = "http://localhost:1234";
const hex = (href) => urlBytes(href, origin, "/")?.toString("hex");

test("a data: face is read whole, a raw comma in its body kept", () => {
  assert.equal(
    hex("data:font/ttf,a%2Cb,c,d"),
    Buffer.from("a,b,c,d").toString("hex"),
  );
});

test("a percent-encoded data: face is its bytes, not UTF-8 text", () => {
  assert.equal(hex("data:font/ttf,%00%01%FF"), "0001ff");
  assert.equal(hex("data:font/ttf,%C3%A9"), "c3a9");
});

test("a base64 data: face is decoded, its marker in any case", () => {
  const body = Buffer.from([0, 1, 255]).toString("base64");
  assert.equal(hex(`data:font/ttf;base64,${body}`), "0001ff");
  assert.equal(hex(`data:font/ttf;BASE64,${body}`), "0001ff");
});

test("a data: URL with no comma has no face", () => {
  assert.equal(urlBytes("data:abc", origin, "/"), null);
});

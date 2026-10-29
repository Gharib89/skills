// The joins measure's face bytes: a data: URL's own, whole.
import { test } from "node:test";
import assert from "node:assert/strict";
import { urlBytes } from "../../skills/creative-video/scripts/lib/backend/joins.mjs";

test("a data: face is read whole, a comma in its body kept", () => {
  const origin = "http://localhost:1234";
  assert.equal(
    urlBytes("data:font/ttf,a%2Cb,c,d", origin, "/").toString("latin1"),
    "a,b,c,d",
  );
  assert.equal(
    urlBytes(
      `data:font/ttf;base64,${Buffer.from("a,b").toString("base64")}`,
      origin,
      "/",
    ).toString("latin1"),
    "a,b",
  );
});

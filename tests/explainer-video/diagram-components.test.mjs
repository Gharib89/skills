// The `diagram` component at compile: nodes and the links between them, laid
// out by the composer, so the scene file holds no coordinates. A link names
// nodes by id, and an id no node holds is refused. It is rich (it draws its
// own frame), so a `camera` key is refused on it.
import { test } from "node:test";
import assert from "node:assert/strict";
import { banReason } from "../../skills/explainer-video/scripts/lib/allowed.mjs";
import { checkVisual } from "../../skills/explainer-video/scripts/lib/visuals.mjs";

const said = [
  "The client sends a request.",
  "The server reads the cache.",
  "Then it answers the client.",
];
const diagram = (nodes, links) => ({
  component: "diagram",
  props: { nodes, links },
});
const node = (id, at, label = id, more = {}) => ({ id, at, label, ...more });
const link = (from, to, at, more = {}) => ({ from, to, at, ...more });
const NODES = [
  node("client", 1, "Client"),
  node("server", 2, "Server"),
  node("cache", 2, "Cache", { on: "the cache", note: "redis" }),
];
const bad = (visual, why) =>
  assert.throws(() => checkVisual(visual, said), why);

test("a diagram of nodes and the links between them compiles", () => {
  assert.doesNotThrow(() =>
    checkVisual(
      diagram(NODES, [
        link("client", "server", 2),
        link("server", "cache", 2, { on: "the cache", packets: 2 }),
        link("server", "client", 3),
      ]),
      said,
    ),
  );
});

test("a link naming an unknown node id is refused at compile", () => {
  bad(
    diagram(NODES, [link("client", "db", 2)]),
    /diagram link to "db" names no node \(client, server, cache\)/,
  );
  bad(
    diagram(NODES, [link("api", "server", 2)]),
    /diagram link from "api" names no node/,
  );
});

test("a link never rises before both its nodes", () => {
  bad(
    diagram(NODES, [link("client", "server", 1)]),
    /diagram link client to server lands before node "server" appears \(at 2\)/,
  );
  bad(
    diagram(NODES, [link("server", "cache", 2)]),
    /lands before node "cache" appears \(at 2 on "the cache"\)/,
  );
});

test("a diagram refuses a node id used twice, a self link, a link twice, a stray prop and packets past 3", () => {
  bad(diagram(NODES, [link("server", "server", 2)]), /link server to itself/);
  bad(
    diagram(NODES, [link("client", "server", 2), link("client", "server", 3)]),
    /link client to server is twice/,
  );
  bad(
    diagram(NODES, [link("client", "server", 2, { packets: 4 })]),
    /packets is not 1 to 3/,
  );
  bad(
    diagram(NODES, [link("client", "server", 2, { x: 10 })]),
    /a diagram link has no prop x/,
  );
  bad(
    diagram([node("a", 1, "A", { y: 4 }), node("b", 1)], [link("a", "b", 1)]),
    /a diagram node has no prop y/,
  );
  bad(
    diagram([node("a", 1), node("b", 1), node("a", 2)], [link("a", "b", 2)]),
    /node id "a" is used twice/,
  );
});

test("a diagram is rich: it draws its own camera, so a camera key is refused", () => {
  bad(
    { ...diagram(NODES, [link("client", "server", 2)]), camera: { at: 2 } },
    /diagram draws its own camera, so it takes no camera key/,
  );
});

test("a diagram wider or taller than a frame holds is refused at compile", () => {
  const chain = (n) => Array.from({ length: n }, (_, i) => node(`n${i}`, 1));
  const links = (n) =>
    Array.from({ length: n - 1 }, (_, i) => link(`n${i}`, `n${i + 1}`, 1));
  // five columns pass, six do not
  assert.doesNotThrow(() => checkVisual(diagram(chain(5), links(5)), said));
  bad(
    diagram(chain(6), links(6)),
    /diagram lays out 6 columns of up to 1 nodes; a frame holds 5 of up to 3/,
  );
  // a hub fanning out to three fits, to four does not
  const fan = (k) =>
    diagram(
      chain(k + 1),
      Array.from({ length: k }, (_, i) => link("n0", `n${i + 1}`, 1)),
    );
  assert.doesNotThrow(() => checkVisual(fan(3), said));
  bad(fan(4), /2 columns of up to 4 nodes/);
});

test("a profile that bans draw bars the diagram, whose arrows stroke on", () => {
  assert.match(
    banReason(["draw"], "diagram", "plain"),
    /component diagram uses draw, which style profile plain bans/,
  );
});

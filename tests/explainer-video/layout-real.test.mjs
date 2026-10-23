// The layout probe in real Chrome, judged by the layout gate: a code excerpt
// whose indent is lost, a card cut by a `clip-path` edge, and a card cut by a
// clipping ancestor beyond the nearest, each failing beside a card that passes.
// Split from the gates-* tests, whose probe is canned, so the turn rung leaves
// this file out and never starts Chrome. Skipped where the Chrome or npm rows
// are not installed (/explainer-video setup).
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { probe } from "../../skills/explainer-video/scripts/lib/backend/browser.mjs";
import { judge } from "../../skills/explainer-video/scripts/lib/layout.mjs";
import { floors } from "../../skills/explainer-video/scripts/lib/style.mjs";
import {
  catalogue,
  compositionAssets,
  dest,
  hyperframesEnv,
} from "../../skills/explainer-video/scripts/lib/tools.mjs";
import {
  sceneFile,
  videoPage,
} from "../../skills/explainer-video/scripts/render/compose.mjs";
import { FIXTURE } from "../../skills/explainer-video/maintainer/real-render-fixture.mjs";
import { read, skill } from "./render-lib.mjs";

const missing = catalogue()
  .filter((r) => ["npm", "chrome"].includes(r.kind))
  .filter((r) => !fs.existsSync(path.join(dest(r), ".stamp")));
const skip = missing.length > 0 && "the Chrome or npm rows are not installed";

const profile = JSON.parse(read(skill, "styles", "claude-code.json"));
const SECONDS = 4;
const timing = {
  id: "s",
  start: 0,
  duration: SECONDS,
  slot: SECONDS,
  sentences: [0.2, 1, 1.8],
  words: Array.from({ length: 12 }, (_, i) => 0.2 + 0.3 * i),
};

// Cards in the content area, none touching another or the safe margin. A card
// is a block wide as its clip leaves it, so a cut shows at its edge.
const CARDS = `<div class="clip-a"><div class="card ok">Inside the clip</div></div>
<div class="clip-b"><div class="card wide">Cut by clip-path</div></div>
<div class="clip-c"><div class="card wide">Cut with pointer events off</div></div>
<div class="clip-d"><div class="card ok">Inside, pointer events off and important</div></div>
<div class="outer-a"><div class="inner-a"><div class="card ok">Inside both clips</div></div></div>
<div class="outer-b"><div class="inner-b"><div class="mid"><div class="card wide">Cut by the outer clip</div></div></div></div>
<style>
.clip-a, .clip-b, .clip-c, .clip-d, .outer-a, .outer-b { position: absolute; left: 160px; width: 700px; height: 90px; }
.clip-a { top: 160px; clip-path: inset(0); }
.clip-b { top: 300px; clip-path: inset(0 100px 0 0); }
.clip-c { top: 720px; clip-path: inset(0 100px 0 0); pointer-events: none; }
.clip-d { left: 900px; top: 160px; clip-path: inset(0); }
.clip-d .card { pointer-events: none !important; }
.outer-a { top: 440px; overflow: hidden; }
.outer-b { top: 580px; width: 500px; overflow: hidden; }
.inner-a { position: absolute; inset: 0; overflow: hidden; }
.inner-b { position: absolute; inset: 0 -200px 0 0; overflow: hidden; }
.mid { position: absolute; inset: 0; overflow: visible; }
.card { position: absolute; left: 0; top: 0; height: 90px; color: var(--text); font: 500 var(--size-body) var(--font-text); }
.ok { width: 600px; }
.wide { width: 650px; }
</style>`;

const SCENES = {
  code: FIXTURE.find((p) => p.scene.id === "code-excerpt").scene,
  cards: {
    id: "cards",
    role: "point",
    title: "Cards",
    narration: ["Six cards."],
    visual: {
      component: "custom",
      props: {
        file: "scenes/cards.html",
        intent: "cards inside and cut by clips",
        cues: [],
        source: CARDS,
      },
    },
  },
};

// The layout findings of a scene drawn as `edit` leaves it, at its last second:
// everything has revealed and nothing moves.
async function findings(scene, edit = (html) => html) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "layout-real-"));
  try {
    const comp = path.join(tmp, "composition");
    fs.mkdirSync(path.join(comp, "scenes"), { recursive: true });
    const fonts = compositionAssets([], comp);
    const html = await sceneFile({ ...scene, id: "s" }, timing, profile, {
      backend: {},
      seam: {},
      dir: "ltr",
    });
    fs.writeFileSync(path.join(comp, "scenes", "s.html"), edit(html));
    fs.writeFileSync(
      path.join(comp, "index.html"),
      videoPage({
        title: "Layout probe",
        profile,
        fonts,
        scenes: [{ id: "s", start: 0, duration: SECONDS, slot: SECONDS }],
        cues: [],
        total: SECONDS,
        audio: false,
      }),
    );
    const out = [];
    judge(
      { layout: { findings: [] }, contrast: { findings: [] } },
      await probe(comp, [SECONDS - 0.5], { env: hyperframesEnv() }),
      floors(profile),
      (gate, t, what) => gate === "layout" && out.push(what),
    );
    return out;
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

test(
  "a code excerpt's indented line passes, and fails once its indent is lost",
  { skip },
  async () => {
    assert.deepEqual(await findings(SCENES.code), []);
    const lost = await findings(SCENES.code, (html) =>
      html.replace(
        /(\.xcode \.xt \{[^}]*)white-space: pre;/,
        "$1white-space: normal;",
      ),
    );
    assert.deepEqual(lost, ['indent lost, 2 leading spaces "cache.clear();"']);
  },
);

test(
  "a card inside its clips passes, and one cut by a clip-path edge or by an outer clipping ancestor fails",
  { skip },
  async () => {
    const found = await findings(SCENES.cards);
    assert.deepEqual(found.toSorted(), [
      'clipped "Cut by the outer clip"',
      'clipped by clip-path "Cut by clip-path"',
      'clipped by clip-path "Cut with pointer events off"',
    ]);
  },
);

// The gates on an Egyptian Arabic run: the joins gate, the reading-direction
// checks the layout gate holds Arabic text to, what only the critic can judge,
// and captions set right to left.
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { cuesOf } from "../../skills/creative-video/scripts/gates/captions.mjs";
import { captionsHtml } from "../../skills/creative-video/scripts/render/project.mjs";
import { calls, project, read, readJson } from "./timing-lib.mjs";
import {
  compose,
  gateLine,
  only,
  record,
  runGates,
  timed,
  timeline,
} from "./gates-lib.mjs";

// Egyptian Arabic narration with English terms kept in Latin letters, as the
// script stage writes it.
const AR_SCENES = [
  {
    id: "hook",
    narration: ["شيب بياخد مهمة واحدة ويوصلها لحد pull request متراجع."],
  },
  {
    id: "context",
    narration: ["الأول بيقرا الـ profile بتاع الريبو."],
  },
  {
    id: "recap",
    narration: ["كل تغيير بيدخل من خلال review قبل الـ merge."],
  },
];
const RTL = (body) => `<section dir="rtl">${body}</section>`;
const LINE = (text) => `<p style="line-height: 1.7">${text}</p>`;
const arabic = (bodies = {}) =>
  timed(
    {
      hook: RTL(LINE("شيب بيوصل المهمة")),
      context: RTL(LINE("بيقرا البروفايل")),
      recap: RTL(LINE("كل تغيير بيتراجع")),
      ...bodies,
    },
    { scenes: AR_SCENES, language: "ar" },
  );

test("an Arabic word split where the browser shapes alone fails the joins gate, naming the word and its face; unsplit it passes", () => {
  const fx = arabic({
    hook: RTL(`<p style="line-height: 1.7" data-joins-broken="كتب">كتب</p>`),
  });
  let r = runGates(fx);
  assert.equal(r.code, 1, r.out + r.err);
  only(r, "joins");
  assert.match(
    gateLine(r, "joins"),
    /^fail: 1 finding\(s\), first: \d+\.\d\d s hook: "كتب" breaks its joins in Noto Naskh Arabic \(3 samples\) vs every Arabic word shaped as one in the face it is drawn in$/,
  );
  compose(fx, "hook", RTL(LINE("كتب")));
  r = runGates(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(gateLine(r, "joins"), /^pass: \d+ split word\(s\) shaped vs /);
});

test("the probe shapes the sample frames of an Arabic run and no frame of an English one", () => {
  const fx = arabic();
  runGates(fx);
  const probed = calls(fx).find((c) => c.call === "probe");
  const samples = timeline(fx).scenes.length * 3;
  assert.equal(probed.joins.length, samples);
  assert.ok(probed.joins.every((t) => probed.times.includes(t)));

  const en = timed();
  const r = runGates(en);
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(gateLine(r, "joins"), undefined);
  assert.deepEqual(calls(en).find((c) => c.call === "probe").joins, []);
});

test("an unresolvable face and a reversed Latin run go to the critic's rtl checks, not to a gate", () => {
  const fx = arabic({
    hook: RTL(
      `<p style="line-height: 1.7" data-joins-unresolved="كتب">كتب</p><span data-joins-reversed="2026">٢٠٢٦</span>`,
    ),
  });
  const r = runGates(fx, {}, { critic: false });
  assert.match(gateLine(r, "joins"), /^pass: /);
  assert.match(gateLine(r, "critic"), /^pending: /);
  const checks = readJson(
    path.join(fx.dir, record(fx).gates.critic.stills, "checks.json"),
  );
  assert.deepEqual(checks, {
    hook: [
      '"كتب": its face (Noto Naskh Arabic) did not resolve to a file to shape it in',
      '"2026": a Latin or digit run split into boxes, read right to left',
    ],
  });
});

test("the dir, isolated-Latin and line-height checks fail the layout gate of an Arabic run", () => {
  const fx = arabic({
    hook: `<p>شيب بيوصل المهمة</p>`,
    context: RTL(`${LINE("بيقرا البروفايل")}<span>React</span>`),
    recap: RTL(`<p style="line-height: 1.1">كل تغيير</p>`),
  });
  const r = runGates(fx);
  only(r, "layout");
  const lines = record(fx).gates.layout.evidence.map((l) =>
    l.replace(/^\d+\.\d\d s /, ""),
  );
  assert.deepEqual(lines, [
    'hook: Arabic reads ltr "شيب بيوصل المهمة" (3 samples)',
    'context: Latin run not isolated "React" (3 samples)',
    'context: Latin run wraps "React" (3 samples)',
    'recap: line height 1.1 under the ink 1.4 of Noto Naskh Arabic "كل تغيير" (3 samples)',
  ]);
  compose(fx, "hook", RTL(LINE("شيب بيوصل المهمة")));
  compose(
    fx,
    "context",
    RTL(
      `${LINE("بيقرا البروفايل")}<bdi style="white-space: nowrap">React</bdi>`,
    ),
  );
  // A line height equal to the ink passes, and `normal` (no line height set)
  // takes the face's own metrics, so it is not measured.
  compose(
    fx,
    "recap",
    RTL(`<p style="line-height: 1.4">كل تغيير</p><p>بيتراجع</p>`),
  );
  assert.equal(runGates(fx).code, 0);
});

test("Arabic captions read right to left in an Arabic face, each Latin run isolated on one line, and read back as the timeline's cues", () => {
  const fx = arabic();
  const html = read(project(fx, "compositions", "captions.html"));
  assert.match(
    html,
    /src: url\("assets\/ibm-plex-sans-arabic-600\.woff2"\) format\("woff2"\);/,
  );
  assert.equal(
    read(project(fx, "assets", "ibm-plex-sans-arabic-600.woff2")),
    "wOF2",
  );
  assert.match(html, /font: 600 44px "IBM Plex Sans Arabic", sans-serif;/);
  assert.match(html, /line-height: 1\.7;/);
  assert.match(
    html,
    /\.lat \{\s*unicode-bidi: isolate;\s*white-space: nowrap;\s*\}/,
  );
  const cue = html.match(/<div class="cue clip"[^>]*>.*<\/div>/)[0];
  assert.match(cue, / dir="rtl"/);
  assert.match(
    cue,
    /<bdi class="lat" dir="ltr"><span class="w">pull<\/span> <span class="w">request<\/span><\/bdi>/,
  );
  assert.deepEqual(
    cuesOf(html).map((c) => c.text),
    timeline(fx).cues.map((c) => c.text),
  );
});

test("a number after a Latin word in an Arabic caption is isolated with it, so GPT 4 does not read 4 GPT", () => {
  const cue = (texts) =>
    captionsHtml(
      [{ start: 0, end: 1, tokens: texts.map((text) => ({ text })) }],
      "ar",
    );
  assert.match(
    cue(["جرّبت", "GPT", "4", "النهارده"]),
    /<bdi class="lat" dir="ltr"><span class="w">GPT<\/span> <span class="w">4<\/span><\/bdi> <span class="w">النهارده/,
  );
  assert.match(
    cue(["سنة", "2026"]),
    /<span class="w">سنة<\/span> <span class="w">2026<\/span><\/div>/,
  );
});

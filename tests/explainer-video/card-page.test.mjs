// The style card page, part 2: the inline page script run in a vm against the
// documented card fields.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import {
  answer,
  built,
  clone,
  doc,
  fixture,
  html,
  json,
  latestCard,
  shape,
  shapeProblems,
} from "./card-lib.mjs";

// The page's code, run with no document so it boots nothing and exposes its core.
const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(
  (m) => m[1],
);
const ctx = vm.createContext({ console });
vm.runInContext(
  scripts[0] +
    "\n;globalThis.__page = { newState, setCards, setAnswers, view, ACT, answersDoc, answersText, frameDoc, failing, mediaUrl, buildUrl };",
  ctx,
);
const P = ctx.__page;
const seen = new Set();
function watch(v, p) {
  if (!v || typeof v !== "object") return v;
  return new Proxy(v, {
    get(t, k, r) {
      if (typeof k === "symbol") return Reflect.get(t, k, r);
      if (Array.isArray(t))
        return /^\d+$/.test(k) ? watch(t[k], p + "[]") : Reflect.get(t, k, r);
      seen.add(p + "." + k);
      return watch(t[k], p + "." + k);
    },
  });
}
function session(docs, answered = []) {
  const S = P.newState("Style card: Acme");
  P.setCards(
    S,
    docs.map((d) => watch(clone(d), "card")),
  );
  P.setAnswers(S, answered);
  P.view(S);
  return S;
}
const submitOff = (v) => /<button[^>]*id="submit"[^>]*\sdisabled/.test(v);

test("the page is one inline code script with the title placeholder once and an empty embedded card", () => {
  assert.equal(scripts.length, 1);
  assert.doesNotThrow(() => new vm.Script(scripts[0]));
  assert.match(html, /<title>\{\{TITLE\}\}<\/title>/);
  assert.equal(html.split("{{TITLE}}").length, 2);
  assert.match(
    html,
    /<script type="application\/json" id="card">null<\/script>/,
  );
  // A local page returns at its capability check, so its listeners come first.
  const code = scripts[0];
  for (const ev of ["click", "change", "input"])
    assert.ok(
      code.indexOf(`document.addEventListener('${ev}'`) <
        code.indexOf("return localMode()"),
      ev,
    );
  // A frame runs no script but stays readable for the live palette.
  assert.match(html, /<iframe sandbox="allow-same-origin" /);
});

test("the page reads only documented card fields, and its answers match the shape and apply back to the same answers", () => {
  const fx = fixture();
  built(fx);
  const c = latestCard(fx);
  const S = session([c]);
  const v = P.view(S);
  assert.equal(v.split("<iframe").length - 1, 6);
  assert.ok(submitOff(v));
  P.ACT.set(S, { field: "choice", value: "save" });
  P.ACT.set(S, { field: "name", value: "acme-brand" });
  P.ACT.set(S, { field: "default", value: true });
  P.ACT.set(S, { field: "note", value: "keep\nthe red" });
  assert.ok(!submitOff(P.view(S)));
  const a = clone(P.answersDoc(S, "2026-10-16T10:00:00Z"));
  assert.deepEqual(shapeProblems(a, "answers"), []);
  assert.deepEqual(a, {
    version: 1,
    submittedAt: "2026-10-16T10:00:00Z",
    choice: "save",
    name: "acme-brand",
    colors: {},
    type: {},
    note: "keep\nthe red",
    replace: false,
    default: true,
  });
  for (const f of seen)
    assert.ok(
      shape.has(f.replace(/\[\]$/, "")),
      `the page reads undocumented ${f}`,
    );
  const text = P.answersText(S);
  for (const line of text.split("\n")) {
    const form = line
      .replace(/\d+/g, "<n>")
      .replace(/^Name: .*/, "Name: <name>")
      .replace(/^Note: .*/, "Note: <text>");
    assert.ok(
      doc.includes("`" + form + "`") || doc.includes(line.slice(0, 8)),
      line,
    );
  }
  const r = answer(fx, text);
  assert.equal(r.code, 0, r.out + r.err);
  const back = json(fx.dir, "style-draft", "card", "answers-1.json");
  assert.deepEqual(
    { ...back, submittedAt: a.submittedAt },
    { ...a, note: "keep the red" },
  );
});

test("the frame most in view mounts a live iframe over its poster, and the grammar panel lists each field with its mark", () => {
  const fx = fixture({
    grammar: { seams: { family: "velocity", blur: 12 } },
    grammarMarks: {
      "seams.blur": { mark: "measured", why: "blur 0.5, 12 px" },
    },
  });
  built(fx);
  const c = latestCard(fx);
  const S = session([c]);
  const live = 'sandbox="allow-scripts"';
  assert.ok(!P.view(S).includes(live), "no frame is live until one is in view");
  S.inView = { seam: true };
  const v = P.view(S);
  assert.equal(v.split(live).length - 1, 1);
  assert.match(v, /<iframe sandbox="allow-scripts"[^>]*data-play="seam"/);
  // refresh() swaps the data-live parts while the user types: the playing
  // iframe is not one of them, or it would come back empty.
  assert.doesNotMatch(v, /<iframe[^>]*data-live=/);
  assert.equal(P.buildUrl(c), "live.js");
  c.live.url = "javascript:alert(1)";
  assert.equal(P.buildUrl(c), "");
  assert.match(v, /<h2>Grammar<\/h2>/);
  assert.match(
    v,
    /seams\.blur<\/span>\s*<span>12<\/span><span class="why"><span class="tag accent">measured<\/span><span>blur 0\.5, 12 px<\/span>/,
  );
  assert.match(
    v,
    /<span class="label">ease<\/span>\s*<span>velocity<\/span><span class="why"><span class="tag">default<\/span><\/span>/,
  );
});

test("a colour edit recolours the frames, fails contrast live and blocks Submit until fixed", () => {
  const fx = fixture();
  built(fx);
  const c = latestCard(fx);
  const S = session([c]);
  P.ACT.set(S, { field: "choice", value: "once" });
  P.ACT.color(S, { token: "muted", hex: "#c8c8c0" });
  const v = P.view(S);
  assert.ok(submitOff(v));
  assert.ok(
    P.failing(S).some((x) => /^muted on bg [\d.]+:1, floor 4\.5:1$/.test(x)),
  );
  assert.match(v, /muted on bg/);
  const frame = P.frameDoc(S, c.frames[0]);
  assert.match(frame, /<style id="edits">:root \{[^}]*--muted: #c8c8c0;/);
  assert.ok(!/<script/i.test(frame), "a frame carries no script");
  P.ACT.color(S, { token: "muted", hex: "#3a3f63" });
  assert.deepEqual(clone(P.failing(S)), []);
  assert.ok(!submitOff(P.view(S)));
  assert.deepEqual(clone(P.answersDoc(S).colors), { muted: "#3a3f63" });
  assert.match(P.answersText(S), /^Colour muted: #3a3f63$/m);
});

test("frames load their fonts from the card's URLs, and a URL that is not https, /_blob/ or relative is dropped", () => {
  const fx = fixture();
  built(fx);
  const c = latestCard(fx);
  c.fonts = c.fonts.map((f, i) => ({
    ...f,
    url: i ? `https://cdn.example/${f.file}` : "javascript:alert(1)",
  }));
  const frame = P.frameDoc(session([c]), c.frames[0]);
  assert.ok(!frame.includes("javascript:"));
  assert.match(frame, /url\("https:\/\/cdn\.example\/[^"]+"\)/);
  assert.match(frame, /url\(""\)/);
  for (const bad of ['a")', "/abs", "data:x", "a b", "x\\y"])
    assert.equal(P.mediaUrl(bad), "", bad);
  for (const ok of ["frames/fonts/a.woff2", "https://x/a", "/_blob/abc"])
    assert.equal(P.mediaUrl(ok), ok);
});

test("a name the store holds needs Replace before Save; findings block Save and Use once until an edit or a revision", () => {
  const fx = fixture();
  fs.mkdirSync(fx.project, { recursive: true });
  fs.writeFileSync(path.join(fx.project, "acme.json"), "{}");
  built(fx);
  const c = latestCard(fx);
  assert.deepEqual(c.taken, ["acme"]);
  const S = session([c]);
  P.ACT.set(S, { field: "choice", value: "save" });
  assert.ok(submitOff(P.view(S)));
  assert.match(P.view(S), /Replace the saved acme/);
  P.ACT.set(S, { field: "replace", value: true });
  assert.ok(!submitOff(P.view(S)));
  assert.equal(P.answersDoc(S).replace, true);

  const red = {
    ...clone(c),
    findings: ["layout title: text 12 px, floor 18 px"],
  };
  const R = session([red]);
  assert.match(P.view(R), /class="banner panel" role="alert"/);
  P.ACT.set(R, { field: "choice", value: "once" });
  assert.ok(submitOff(P.view(R)));
  P.ACT.set(R, { field: "choice", value: "revise" });
  assert.ok(!submitOff(P.view(R)));
  P.ACT.set(R, { field: "choice", value: "once" });
  P.ACT.font(R, { role: "title", font: "inter" });
  assert.ok(!submitOff(P.view(R)));
  assert.deepEqual(clone(P.answersDoc(R).type), { title: "inter" });
});

test("an answered version locks the page; a viewer who cannot edit sees no Submit", () => {
  const fx = fixture();
  built(fx);
  const c = latestCard(fx);
  const S = session([c], [{ version: 1 }]);
  assert.match(P.view(S), /<b>Submitted\.<\/b>/);
  assert.match(
    P.view(S),
    /<input type="radio" name="choice" value="save"\s+disabled>/,
  );
  const V = session([c]);
  V.canEdit = false;
  assert.ok(!P.view(V).includes('id="submit"'));
});

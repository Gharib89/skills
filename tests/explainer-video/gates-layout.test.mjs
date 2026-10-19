// The video gates through their process doors, part 2: layout, contrast,
// loudness, captions and right to left checks, each failing and passing on the fix.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { judged } from "./critic.mjs";
import { ARABIC, SCRIPT } from "./scene-file.mjs";
import {
  assertGreen,
  assertRed,
  delivered,
  fixture,
  read,
  record,
  render,
  stage,
  titled,
} from "./gates-lib.mjs";

test("a clipped title fails layout, delivers nothing, and passes on the fix", () => {
  const fx = fixture();
  const r = render(fx, titled("clipped"));
  assertRed(fx, r, "layout", 'text_box_overflow "Issue to clipped request"');
  assert.match(
    r.out,
    /^gate layout: fail: \d+ finding\(s\), first: [\d.]+ s hook: /m,
  );
  assert.match(r.err, /^render: the gates did not pass: nothing delivered/m);
  const ev = record(fx).gates.layout.evidence;
  for (const kind of [
    "text_box_overflow",
    "overflow 4000x48 in 1600x48",
    "clipped",
  ]) {
    // A defect held across the scene is one line, counting its samples.
    const hits = ev.filter((e) => e.includes(`: ${kind}`));
    assert.equal(hits.length, 1, `${kind}: ${hits.join(" | ")}`);
    assert.match(hits[0], /\(\d+ samples\)$/);
  }
  assert.match(read(fx.dir, "gates.md"), /^## layout$/m);
  assertGreen(fx, render(fx, SCRIPT));
});

test("a tiny title fails layout as small text, and passes on the fix", () => {
  const fx = fixture();
  assertRed(
    fx,
    render(fx, titled("tiny")),
    "layout",
    'small 12 px "Issue to tiny request"',
  );
  assertGreen(fx, render(fx, SCRIPT));
});

test("a title in the margin fails layout as outside the safe margin, and passes on the fix", () => {
  const fx = fixture();
  assertRed(
    fx,
    render(fx, titled("edge")),
    "layout",
    'outside the safe margin "Issue to edge request"',
  );
  assertGreen(fx, render(fx, SCRIPT));
});

test("a title stacked on the kicker fails layout as an overlap, and passes on the fix", () => {
  const fx = fixture();
  assertRed(
    fx,
    render(fx, titled("stacked")),
    "layout",
    '"Ship" overlaps "Issue to stacked request"',
  );
  assertGreen(fx, render(fx, SCRIPT));
});

test("a contrast error from HyperFrames' check fails contrast", () => {
  const fx = fixture();
  const r = render(fx, SCRIPT, {
    EXPLAINER_VIDEO_FAKE_CHECK: JSON.stringify({
      ok: false,
      layout: { findings: [] },
      contrast: {
        findings: [
          {
            code: "low_contrast",
            severity: "error",
            time: 0,
            text: "x",
            ratio: 2.1,
            requiredRatio: 4.5,
          },
        ],
      },
    }),
  });
  assertRed(fx, r, "contrast", 'low_contrast "x" 2\\.1:1 under 4\\.5:1');
});

test("a dim title fails contrast on the frames, and passes on the fix", () => {
  const fx = fixture();
  assertRed(
    fx,
    render(fx, titled("dim")),
    "contrast",
    '"Issue to dim request" #c8c8c0 on #f5f4ed 1\\.\\d\\d:1 under 3:1',
  );
  assertGreen(fx, render(fx, SCRIPT));
});

test("small text in the accent is held to the body floor on the frames", () => {
  const fx = fixture();
  assertRed(
    fx,
    render(fx, titled("small")),
    "contrast",
    '"Issue to small request" #cc6c54 on #f5f4ed 3\\.26:1 under 4\\.5:1',
  );
  assertGreen(fx, render(fx, SCRIPT));
});

test("a hot mix fails loudness, and passes when the mix is fixed", () => {
  const fx = fixture();
  const r = render(fx, undefined, {
    EXPLAINER_VIDEO_FAKE_PROBE: '{"lufs":-9,"peak":0.4}',
  });
  assertRed(
    fx,
    r,
    "loudness",
    "-9\\.0 LUFS, peak 0\\.4 dBTP vs -14 \\+-1 LUFS",
  );
  assert.deepEqual(record(fx).gates.loudness.evidence, [
    "integrated -9.0 LUFS is 5.0 LU off -14",
    "true peak 0.4 dBTP over -1",
  ]);
  assertGreen(
    fx,
    judged(fx.dir, () => stage(fx, "render/render.mjs")),
  );
});

test("an SRT edited after a green render fails captions in the gates stage alone, which deletes nothing", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  const srt = path.join(fx.dir, "out", "demo.srt");
  const good = read(srt);
  fs.writeFileSync(srt, good.replace("merged pull request", "merged request"));
  const r = stage(fx, "gates/gates.mjs");
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.out,
    /^gate captions: fail: \d+ cue\(s\), 1 finding\(s\), first: SRT cue 1 reads "Ship drives #626 to a merged request\.", the composition "Ship drives #626 to a merged pull request\." vs none$/m,
  );
  assert.ok(fs.existsSync(srt));
  fs.writeFileSync(srt, good);
  const fixed = stage(fx, "gates/gates.mjs");
  assert.equal(fixed.code, 0, fixed.out + fixed.err);
  assert.equal(record(fx).gates.captions.attempts, 0);
});

test("an Arabic render passes the right to left checks, and each broken reading rule fails layout", () => {
  const fx = fixture(ARABIC);
  fx.env.GEMINI_API_KEY = "test-key";
  const green = render(fx);
  assert.equal(green.code, 0, green.out + green.err);
  const index = path.join(fx.dir, "composition", "index.html");
  const good = read(index);
  for (const [broken, why] of [
    [
      good.replace('<html lang="ar">', '<html lang="ar" dir="rtl">'),
      "dir on the page root html",
    ],
    [good.replaceAll(' dir="rtl"', ""), 'Arabic reads ltr "'],
    [
      good.replace("var(--size-body)/1.7", "var(--size-body)/1.3"),
      'line height 1.3 under the ink 1.35 of ibm-plex-sans-arabic "',
    ],
    [
      good.replace(" white-space: nowrap;", ""),
      'Latin run wraps "pull request"',
    ],
    [
      good.replace(
        " white-space: nowrap;",
        " white-space: nowrap; unicode-bidi: normal;",
      ),
      'Latin run not isolated "pull request"',
    ],
    [
      good.replaceAll('<bdi class="lat">pull request</bdi>', "pull request"),
      'Latin run not isolated in "',
    ],
  ]) {
    fs.writeFileSync(index, broken);
    fs.rmSync(path.join(fx.dir, ".cache", "gates"), { recursive: true });
    const r = stage(fx, "gates/gates.mjs");
    assert.equal(r.code, 1, r.out + r.err);
    assert.match(r.out, /^gate layout: fail: /m);
    assert.ok(
      record(fx).gates.layout.evidence.some((e) => e.includes(why)),
      `${why}: ${record(fx).gates.layout.evidence.join(" | ")}`,
    );
  }
  fs.writeFileSync(index, good);
  fs.rmSync(path.join(fx.dir, ".cache", "gates"), { recursive: true });
  const fixed = stage(fx, "gates/gates.mjs");
  assert.equal(fixed.code, 0, fixed.out + fixed.err);
});

test("an English run quoting an Arabic word is not held to the right to left reading rules", () => {
  const fx = fixture();
  const r = render(fx, SCRIPT.replace('"value": "code"', '"value": "كود"'));
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(r.out, /^gate layout: pass: /m);
});

test("Arabic text in a code frame, which reads left to right as written, passes the reading checks", () => {
  const fx = fixture(ARABIC.replace("\\ngh pr create", '\\necho \\"تم\\"'));
  fx.env.GEMINI_API_KEY = "test-key";
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(r.out, /^gate layout: pass: /m);
});

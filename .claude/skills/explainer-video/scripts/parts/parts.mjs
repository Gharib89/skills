// The part plan of a request over five minutes: offered after the source stage,
// accepted as `parts.json` or declined, and each part started as a run folder
// of its own under `<run>/parts/`.
//
//   node parts.mjs <run-folder> offer
//   node parts.mjs <run-folder> decline
//   node parts.mjs <run-folder> check
//   node parts.mjs <run-folder> start <n>
//
// Reads <run>/brief.json. `offer` prints `parts: no offer, <m> min is within 5`
// for a short request, else the fewest parts (each 2 to 5 minutes) and the
// first-render estimate of parts and of one long video; `decline` records
// `{ "declined": true, "length": <min> }` in <run>/parts.json, held only while
// the brief asks that length, and prints one line with the estimate; `check`
// holds the plan the agent wrote into parts.json (each part's
// title, focus, minutes, excerpts and the must items it says) to the brief and
// the pack, one line a part; `start <n>` makes part n's run folder under
// <run>/parts/ once the part before it is delivered, with the bridge back to
// that part and the operator's notes on it.
// exit: 0 · 1 `parts: <why>` on stderr · 2 usage
import fs from "node:fs";
import path from "node:path";
import { estimate, loadRates } from "../lib/estimate.mjs";
import { HOLD, LONG, PART } from "../lib/length.mjs";
import { writeIgnore } from "../lib/runfolder.mjs";
import { findStyle, grammar } from "../lib/style.mjs";

const [run, cmd, ...args] = process.argv.slice(2);
const commands = ["offer", "decline", "check", "start"];
if (
  !run ||
  !commands.includes(cmd) ||
  args.length !== (cmd === "start" ? 1 : 0)
) {
  console.error(
    `usage: node parts.mjs <run-folder> ${commands.join("|").replace("start", "start <n>")}`,
  );
  process.exit(2);
}
const file = (...p) => path.join(run, ...p);
function fail(why) {
  console.error(`parts: ${why}`);
  process.exit(1);
}
const num = (x) => String(+x.toFixed(2));

// The JSON in `f`, or a refusal naming the file when it does not parse.
function readJson(f) {
  try {
    return JSON.parse(fs.readFileSync(f, "utf8"));
  } catch (e) {
    fail(`${path.basename(f)} is not valid JSON: ${e.message}`);
  }
}

if (!fs.existsSync(file("brief.json")))
  fail("no brief.json: run brief.mjs first");
const brief = readJson(file("brief.json"));
if (!brief || typeof brief !== "object" || Array.isArray(brief))
  fail("brief.json is not an object");
if (!Number.isFinite(brief.length)) fail("brief.json length is not a number");
if (typeof brief.style !== "string") fail("brief.json style is not a name");
const length = brief.length;
// A decline holds for the length it was made at: a brief changed since is
// offered the split again.
const saved = fs.existsSync(file("parts.json"))
  ? readJson(file("parts.json"))
  : null;
const held = saved?.declined && saved.length !== length ? null : saved;

// The fewest parts take ceil(length / 5) of them, each the even share to a
// tenth of a minute, the last holding the rest.
function proposal() {
  const n = Math.ceil(length / PART.max);
  const share = Math.round((length / n) * 10) / 10;
  const lengths = Array.from({ length: n - 1 }, () => share);
  lengths.push(+(length - share * (n - 1)).toFixed(2));
  return lengths;
}

// Render and gates seconds as minutes to a tenth, for a video of `lengths`
// minutes rendered one video after another.
function minutes(lengths) {
  const { profile } = findStyle(run, brief.style);
  const { texture } = grammar(profile);
  const { rates } = loadRates();
  const textured = texture.surface !== "flat" || texture.overlays.length > 0;
  const each = lengths.map(
    (m) =>
      estimate([{ id: "all", seconds: m * 60 - HOLD }], rates, { textured })
        .seconds,
  );
  const r1 = (s) => Math.round((s / 60) * 10) / 10;
  return { first: r1(each[0]), all: r1(each.reduce((a, b) => a + b, 0)) };
}

// The plan's findings, one line each, against the brief and the pack.
function problems(plan) {
  const out = [];
  if (!Array.isArray(plan.parts) || !plan.parts.length)
    return ["parts.json holds no parts list"];
  const bad = plan.parts.findIndex((p) => !p || typeof p !== "object");
  if (bad >= 0) return [`part ${bad + 1} is not an object`];
  const strings = (v) =>
    Array.isArray(v) && v.every((x) => typeof x === "string");
  for (const [i, p] of plan.parts.entries()) {
    if (typeof p.minutes !== "number")
      return [`part ${i + 1}: minutes is not a number`];
    for (const k of ["excerpts", "must"])
      if (p[k] !== undefined && !strings(p[k]))
        return [`part ${i + 1}: ${k} is not a list of ids`];
  }
  if (!fs.existsSync(file("excerpts.json")))
    return ["no excerpts.json: run pack.mjs first"];
  if (!strings(brief.must)) return ["brief.json must is not a list"];
  const pack = readJson(file("excerpts.json"));
  if (!Array.isArray(pack.excerpts))
    return ["excerpts.json holds no excerpts list"];
  const odd = pack.excerpts.findIndex((x) => typeof x?.id !== "string");
  if (odd >= 0)
    return [`excerpts.json excerpt ${odd + 1} is not an object with an id`];
  const ids = new Set(pack.excerpts.map((x) => x.id));
  const owner = new Map();
  plan.parts.forEach((p, i) => {
    const n = i + 1;
    for (const k of ["title", "focus"])
      if (typeof p[k] !== "string" || !p[k].trim())
        out.push(`part ${n} has no ${k}`);
    if (!(p.minutes >= PART.min && p.minutes <= PART.max))
      out.push(
        `part ${n}: ${p.minutes} min is outside ${PART.min} to ${PART.max}`,
      );
    if (!p.excerpts?.length) out.push(`part ${n} has no excerpts`);
    for (const id of p.excerpts ?? []) {
      if (!ids.has(id)) out.push(`part ${n}: ${id} is not in excerpts.json`);
      else if (owner.has(id))
        out.push(`${id} is in part ${owner.get(id)} and part ${n}`);
      else owner.set(id, n);
    }
    for (const m of p.must ?? [])
      if (!brief.must.includes(m))
        out.push(`part ${n} must "${m}" is not in the brief's must`);
  });
  const total = plan.parts.reduce((a, p) => a + p.minutes, 0);
  if (Math.abs(total - length) > 0.05)
    out.push(`the parts run ${num(total)} min, the brief asks ${num(length)}`);
  for (const m of brief.must)
    if (!plan.parts.some((p) => p.must?.includes(m)))
      out.push(`must "${m}" is in no part`);
  return out;
}

// The folder a part's run folder takes under `<run>/parts/`.
const folder = (n, title) =>
  `${String(n).padStart(2, "0")}-${
    title
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "") || "part"
  }`;

// The operator's notes on a delivered part, from its latest board answers: a
// scene's note, a kept term respelt, a brief change.
function notesOn(dir) {
  const board = path.join(dir, "board");
  const latest = fs.existsSync(board)
    ? fs
        .readdirSync(board)
        .map((f) => f.match(/^answers-(\d+)\.json$/))
        .filter(Boolean)
        .sort((a, b) => b[1] - a[1])[0]
    : null;
  if (!latest) return [];
  const name = latest[0];
  const a = readJson(path.join(board, name));
  if (!a || typeof a !== "object" || Array.isArray(a))
    fail(`${name} is not an object`);
  // One field's entries, each held to `kind` with a named refusal.
  const entries = (key, kind, ok) => {
    const list = a[key] ?? [];
    if (!Array.isArray(list)) fail(`${name} ${key} is not a list`);
    list.forEach((x, i) => {
      if (!ok(x)) fail(`${name} ${key} entry ${i + 1} is not ${kind}`);
    });
    return list;
  };
  const obj = (x) => x && typeof x === "object";
  const scenes = entries("scenes", "an object", obj);
  scenes.forEach((s, i) => {
    if (s.note !== undefined && typeof s.note !== "string")
      fail(`${name} scenes entry ${i + 1} note is not text`);
  });
  return [
    ...scenes
      .filter((s) => s.note?.trim())
      .map((s) => `${s.id}: ${s.note.trim()}`),
    ...entries("kept", "an object", obj).map(
      (k) => `kept term ${k.term} -> ${k.to}`,
    ),
    ...entries("brief", "text", (b) => typeof b === "string").map(
      (b) => `brief ${b}`,
    ),
  ];
}

// Whether `dir`'s render delivered its video: its manifest names the videos
// folder and the video stands in it.
function delivered(dir) {
  const manifest = path.join(dir, "manifest.json");
  const out = fs.existsSync(manifest) ? readJson(manifest)?.delivered : null;
  return (
    typeof out === "string" &&
    fs.existsSync(path.join(out, `${path.basename(dir)}.mp4`))
  );
}

// Writes `text` to `target` unless it already holds it, so a stage's cache
// stays as old as what it was made from. True when it replaced other text.
function keep(target, text) {
  const had = fs.existsSync(target);
  if (had && fs.readFileSync(target, "utf8") === text) return false;
  fs.writeFileSync(target, text);
  return had;
}

function start(n) {
  if (!Number.isInteger(n) || n < 1)
    fail(`part number is 1 or more, got ${args[0]}`);
  if (held?.declined)
    fail("declined, one long video in sections: no parts to start");
  if (!held) fail("no part plan: write parts.json first");
  const found = problems(held);
  if (found.length) fail(found.join("\nparts: "));
  const plan = held.parts;
  if (n > plan.length) fail(`no part ${n}, the plan has ${plan.length}`);
  const at = (i) => file("parts", folder(i + 1, plan[i].title));
  if (n > 1 && !delivered(at(n - 2)))
    fail(`part ${n - 1} is not delivered: finish its render first`);

  const p = plan[n - 1];
  const dir = at(n - 1);
  fs.mkdirSync(dir, { recursive: true });
  const bridge =
    n > 1 ? { title: plan[n - 2].title, excerpts: plan[n - 2].excerpts } : null;
  const notes = n > 1 ? notesOn(at(n - 2)) : [];
  const next = n < plan.length ? { title: plan[n].title } : null;
  const own = path.join(dir, "brief.json");
  const old = fs.existsSync(own) ? readJson(own) : null;
  const now = {
    ...brief,
    focus: p.focus,
    length: p.minutes,
    must: p.must ?? [],
  };
  if (old && JSON.stringify(old) !== JSON.stringify(now)) {
    // As brief.mjs does: the compiled script carries these, and the gates'
    // record belongs to the script being rewritten.
    if (["language", "voice", "style"].some((k) => old[k] !== now[k]))
      fs.rmSync(path.join(dir, "script.json"), { force: true });
    fs.rmSync(path.join(dir, "check.json"), { force: true });
  }
  let changed = false;
  const put = (target, text) => {
    if (keep(target, text)) changed = true;
  };
  put(own, JSON.stringify(now, null, 2) + "\n");
  // A profile only the run holds (the style card's Use once) goes with each
  // part, which looks for its style in its own folder first.
  const style = file("style.json");
  if (fs.existsSync(style) && readJson(style).name === now.style)
    put(path.join(dir, "style.json"), fs.readFileSync(style, "utf8"));
  const pack = readJson(file("excerpts.json"));
  const wanted = new Set([...p.excerpts, ...(bridge?.excerpts ?? [])]);
  put(
    path.join(dir, "excerpts.json"),
    JSON.stringify(
      { ...pack, excerpts: pack.excerpts.filter((x) => wanted.has(x.id)) },
      null,
      2,
    ) + "\n",
  );
  put(
    path.join(dir, "part.json"),
    JSON.stringify(
      {
        series: path.basename(path.resolve(run)),
        n,
        of: plan.length,
        title: p.title,
        focus: p.focus,
        minutes: p.minutes,
        excerpts: p.excerpts,
        bridge,
        next,
        notes,
      },
      null,
      2,
    ) + "\n",
  );
  writeIgnore(dir);
  console.log(
    `parts: part ${n} of ${plan.length} -> parts/${path.basename(dir)}`,
  );
  // A render made from the old recipe is no delivery of the new one: the part
  // after it waits for the part to be rendered again.
  const manifest = path.join(dir, "manifest.json");
  if (changed && fs.existsSync(manifest)) {
    fs.rmSync(manifest);
    console.log(`parts: part ${n} changed since its render: render it again`);
  }
  if (bridge)
    console.log(
      `parts: bridge: part ${n - 1} "${bridge.title}" (${bridge.excerpts.join(", ")})`,
    );
  if (next) console.log(`parts: next: part ${n + 1} "${next.title}"`);
  for (const note of notes)
    console.log(`parts: note from part ${n - 1}, ${note}`);
}

if (cmd === "start") {
  start(Number(args[0]));
} else if (cmd === "check") {
  if (length <= LONG)
    fail(`${num(length)} min is within ${LONG}, no part plan`);
  if (!held) fail("no part plan: write parts.json first");
  if (held.declined) {
    console.log("parts: declined, one long video in sections");
    process.exit(0);
  }
  const found = problems(held);
  if (found.length) fail(found.join("\nparts: "));
  held.parts.forEach((p, i) =>
    console.log(
      `part ${i + 1}: ${p.title} · ${num(p.minutes)} min · ${p.excerpts.length} excerpts`,
    ),
  );
  console.log(`parts: ${held.parts.length} parts, ${num(length)} min`);
} else if (cmd === "decline") {
  if (length <= LONG)
    fail(`${num(length)} min is within ${LONG}, nothing to decline`);
  fs.writeFileSync(
    file("parts.json"),
    JSON.stringify({ declined: true, length }) + "\n",
  );
  console.log(
    `parts: declined, one long video in sections, first render about ${minutes([length]).all} min`,
  );
} else if (length <= LONG) {
  console.log(`parts: no offer, ${num(length)} min is within ${LONG}`);
} else if (held?.declined) {
  console.log("parts: declined earlier, one long video in sections");
} else if (held) {
  console.log("parts: parts.json holds a part plan, run check");
} else {
  const lengths = proposal();
  const parts = minutes(lengths);
  const long = minutes([length]);
  console.log(
    `parts offer: ${num(length)} min is over ${LONG}: ${lengths.length} parts of ${lengths.map(num).join(" + ")} min, or one long video in sections`,
  );
  console.log(
    `parts estimate: ${lengths.length} parts ${parts.all} min in all, the first after ${parts.first} min; one long video ${long.all} min (render and gates, not narration)`,
  );
}

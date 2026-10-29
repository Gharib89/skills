// The sound stage: each sound of the kit's sound.json (the bed and the
// palette) found, licensed and copied into the project.
//
//   node sounds.mjs <run-folder>
//
// For each sound by its `query`: one whose query's record names its `source`,
// that file in the store and in the project, is kept, with no network, so an
// edited query searches again. Else the store's query record (the
// result a query of that kind chose before, on any run) is copied again. Else
// Openverse is searched for CC0 audio (the bed for medium-length clips), a
// search failing after 30 s tried once more, and the first result in a format
// the render plays is downloaded into the store (a failed download counts as
// no result). Else the Kenney packs setup installed are searched by each
// file's name words plus its word-index words (kenney.mjs), a bed only among
// stems marked `loop`. Else the sound is dropped from the kit into its
// `dropped` list, where it replaces an earlier drop of its event, as a sound
// found does. The store is
// <data>/creative-video/sounds/: openverse/<id>.<ext>, kenney/<pack>/<file> and
// queries.json.
// stdout: `sound <event>: openverse <id> | kenney <pack>/<file> | cached |
//         dropped: <why>` per sound (the bed's event is `bed`), and `warn
//         dropped sound: <event>: <why>` per sound dropped
// writes: sound.json with each found sound's source, file
//         (assets/sounds/<name>), licence, creator, url and attribution, the
//         store, and <run>/project/assets/sounds/
// exit:   0 every sound found or dropped · 1 refused, `sounds: <why>` on
//         stderr (no sound.json, a malformed one, or a malformed queries.json:
//         `sounds: <path> is malformed: <why>`) · 2 usage
import fs from "node:fs";
import path from "node:path";
import { readJson } from "../lib/json.mjs";
import { SOUND, kitSounds } from "../lib/kit.mjs";
import { stage } from "../lib/stage.mjs";
import { dest, loadBackend } from "../lib/tools.mjs";
import { AUDIO, indexed } from "./kenney.mjs";

stage("sounds");
const [run, ...rest] = process.argv.slice(2);
if (!run || rest.length) {
  console.error("usage: node sounds.mjs <run-folder>");
  process.exit(2);
}
const kit = readJson(run, SOUND);
// The events this run looks for, the bed's as `bed`.
const asked = new Set(kitSounds(kit).map((s) => s.event));
const backend = await loadBackend();
// Setup's sounds:kenney row lands in the store.
const KENNEY = dest({ kind: "sounds" });
const store = path.dirname(KENNEY);
const assets = path.join(run, "project", "assets", "sounds");
const recordFile = path.join(store, "queries.json");
const records = fs.existsSync(recordFile) ? readRecords() : {};
// The store's query records, each a found sound's fields by `<kind>:<query>`,
// held to the `source` and `file` every reader of a record takes.
function readRecords() {
  const refuse = (why) => {
    throw new Error(`${recordFile} is malformed: ${why}`);
  };
  let v;
  try {
    v = JSON.parse(fs.readFileSync(recordFile, "utf8"));
  } catch (e) {
    refuse(e.message);
  }
  if (!v || typeof v !== "object" || Array.isArray(v))
    refuse("it is not an object");
  for (const [key, r] of Object.entries(v))
    for (const f of ["source", "file"])
      if (typeof r?.[f] !== "string") refuse(`${key}.${f} is not text`);
  return v;
}
// Formats the render plays.
const PLAYS = ["mp3", "ogg", "wav", "flac"];

// A sound's file in the store, from its source and its project file's name.
const stored = ({ source, file }) =>
  source.startsWith("kenney:")
    ? path.join(KENNEY, source.slice(7))
    : path.join(store, "openverse", path.basename(file));

// The first usable CC0 result for `query`, downloaded into the store, or why
// there is none.
async function fromOpenverse(query, medium) {
  let results;
  for (let tries = 1; !results; tries++) {
    try {
      results = await backend.openverse(query, { medium });
    } catch (e) {
      if (tries === 2) return `openverse failed twice (${e.message})`;
    }
  }
  const ext = (r) =>
    (r.filetype || path.extname(r.url ?? "").slice(1)).toLowerCase();
  const r = results.find(
    (r) => r.license === "cc0" && r.url && PLAYS.includes(ext(r)),
  );
  if (!r) return "openverse found no usable CC0 result";
  const name = `${r.id}.${ext(r)}`;
  fs.mkdirSync(path.join(store, "openverse"), { recursive: true });
  try {
    await backend.download(r.url, path.join(store, "openverse", name));
  } catch (e) {
    return `openverse download failed (${e.message})`;
  }
  return {
    source: `openverse:${r.id}`,
    file: `assets/sounds/${name}`,
    licence: [r.license, r.license_version]
      .filter(Boolean)
      .join("-")
      .toUpperCase(),
    creator: r.creator ?? "",
    url: r.foreign_landing_url ?? "",
    attribution: r.attribution ?? "",
  };
}

// Among stems the word index holds (a bed: only those marked `loop`), the
// Kenney file whose name words plus index words hold the most of the query's
// words (a plural counts), the first by path on a tie, or why there is none.
function fromKenney(query, bed) {
  if (!fs.existsSync(path.join(KENNEY, ".stamp")))
    return "the Kenney packs are not installed (run /creative-video setup)";
  const words = query.toLowerCase().match(/[a-z0-9]+/g) ?? [];
  let best = { score: 0 };
  for (const pack of fs.readdirSync(KENNEY).sort()) {
    if (!fs.statSync(path.join(KENNEY, pack)).isDirectory()) continue;
    for (const file of fs.readdirSync(path.join(KENNEY, pack)).sort()) {
      if (!AUDIO.test(file)) continue;
      const entry = indexed(pack, file);
      if (!entry || (bed && !entry.loop)) continue;
      const score = words.filter((w) =>
        entry.words.some((t) => t === w || t === `${w}s` || w === `${t}s`),
      ).length;
      if (score > best.score) best = { score, pack, file };
    }
  }
  if (!best.score)
    return `no Kenney ${bed ? "loop" : "sound"} matches "${query}"`;
  return {
    source: `kenney:${best.pack}/${best.file}`,
    file: `assets/sounds/${best.pack}-${best.file}`,
    licence: "CC0-1.0",
    creator: "Kenney",
    url: `https://kenney.nl/assets/${best.pack}`,
    attribution: `"${best.file}" by Kenney (kenney.nl), CC0 1.0`,
  };
}

// The sound filled, its line's verdict, or `{ why }` to drop it.
async function find(kind, sound) {
  const key = `${kind}:${sound.query}`;
  let found = records[key];
  if (
    found &&
    found.source === sound.source &&
    fs.existsSync(stored(found)) &&
    fs.existsSync(path.join(run, "project", sound.file))
  )
    return { filled: sound, said: "cached" };
  let said = "cached";
  if (!found || !fs.existsSync(stored(found))) {
    const ov = await fromOpenverse(sound.query, kind === "bed");
    const k = typeof ov === "string" && fromKenney(sound.query, kind === "bed");
    found = typeof ov === "string" ? k : ov;
    if (typeof found === "string") return { why: `${ov}; ${k}` };
    said = found.source.replace(":", " ");
    records[key] = found;
  }
  fs.mkdirSync(assets, { recursive: true });
  fs.copyFileSync(stored(found), path.join(run, "project", found.file));
  return { filled: { ...sound, ...found }, said };
}

const dropped = [];
async function each(kind, sound) {
  const event = sound.event ?? "bed";
  const { filled, said, why } = await find(kind, sound);
  if (filled) {
    console.log(`sound ${event}: ${said}`);
    return filled;
  }
  console.log(`sound ${event}: dropped: ${why}`);
  dropped.push({ event, query: sound.query, why });
  return null;
}
if (kit.bed) {
  const bed = await each("bed", kit.bed);
  if (bed) kit.bed = bed;
  else delete kit.bed;
}
if (kit.palette) {
  const out = [];
  for (const s of kit.palette) {
    const filled = await each("palette", s);
    if (filled) out.push(filled);
  }
  kit.palette = out;
}
// This run's outcome for an event replaces its earlier drop.
const kept = (kit.dropped ?? []).filter((d) => !asked.has(d.event));
if (kept.length || dropped.length) kit.dropped = [...kept, ...dropped];
else delete kit.dropped;
for (const d of dropped)
  console.log(`warn dropped sound: ${d.event}: ${d.why}`);
fs.mkdirSync(store, { recursive: true });
fs.writeFileSync(recordFile, JSON.stringify(records, null, 2) + "\n");
fs.writeFileSync(path.join(run, SOUND), JSON.stringify(kit, null, 2) + "\n");

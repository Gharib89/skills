// The sound stage: each sound of the kit's sound.json (the bed and the
// palette) found, licensed and copied into the project.
//
//   node sounds.mjs <run-folder>
//
// For each sound by its `query`: one whose `source` file is in the store and
// in the project is kept, with no network. Else the store's query record (the
// result a query of that kind chose before, on any run) is copied again. Else
// Openverse is searched for CC0 audio (the bed for medium-length clips), a
// search failing after 30 s tried once more, and the first result in a format
// the render plays is downloaded into the store. Else the Kenney packs setup
// installed are searched by their file names' words. Else the sound is dropped
// from the kit into its `dropped` list. The store is
// <data>/creative-video/sounds/: openverse/<id>.<ext>, kenney/<pack>/<file> and
// queries.json.
// stdout: `sound <event>: openverse <id> | kenney <pack>/<file> | cached |
//         dropped: <why>` per sound (the bed's event is `bed`), and `warn
//         dropped sound: <event>: <why>` per sound dropped
// writes: sound.json with each found sound's source, file
//         (assets/sounds/<name>), licence, creator, url and attribution, the
//         store, and <run>/project/assets/sounds/
// exit:   0 every sound found or dropped · 1 refused, `sounds: <why>` on
//         stderr (no sound.json, or a malformed one) · 2 usage
import fs from "node:fs";
import path from "node:path";
import { readJson } from "../lib/json.mjs";
import { SOUND } from "../lib/kit.mjs";
import { stage } from "../lib/stage.mjs";
import { dest, loadBackend } from "../lib/tools.mjs";

stage("sounds");
const [run, ...rest] = process.argv.slice(2);
if (!run || rest.length) {
  console.error("usage: node sounds.mjs <run-folder>");
  process.exit(2);
}
const kit = readJson(run, SOUND);
const backend = await loadBackend();
// Setup's sounds:kenney row lands in the store.
const KENNEY = dest({ kind: "sounds" });
const store = path.dirname(KENNEY);
const assets = path.join(run, "project", "assets", "sounds");
const recordFile = path.join(store, "queries.json");
const records = fs.existsSync(recordFile)
  ? JSON.parse(fs.readFileSync(recordFile, "utf8"))
  : {};
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
  await backend.download(r.url, path.join(store, "openverse", name));
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

// The Kenney file whose name holds the most of the query's words (a plural
// counts), the first by path on a tie, or why there is none.
function fromKenney(query) {
  if (!fs.existsSync(path.join(KENNEY, ".stamp")))
    return "the Kenney packs are not installed (run /creative-video setup)";
  const words = query.toLowerCase().match(/[a-z0-9]+/g) ?? [];
  let best = { score: 0 };
  for (const pack of fs.readdirSync(KENNEY).sort()) {
    if (!fs.statSync(path.join(KENNEY, pack)).isDirectory()) continue;
    for (const file of fs.readdirSync(path.join(KENNEY, pack)).sort()) {
      if (!/\.(ogg|wav|mp3)$/i.test(file)) continue;
      const tokens = file
        .replace(/\.\w+$/, "")
        .replace(/([a-z])([A-Z])/g, "$1 $2")
        .toLowerCase()
        .match(/[a-z]+/g);
      const score = words.filter((w) =>
        tokens.some((t) => t === w || t === `${w}s` || w === `${t}s`),
      ).length;
      if (score > best.score) best = { score, pack, file };
    }
  }
  if (!best.score) return `no Kenney file name matches "${query}"`;
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
  const inProject = (s) =>
    s.source &&
    fs.existsSync(stored(s)) &&
    fs.existsSync(path.join(run, "project", s.file));
  if (inProject(sound)) return { filled: sound, said: "cached" };
  const key = `${kind}:${sound.query}`;
  let found = records[key];
  let said = "cached";
  if (!found || !fs.existsSync(stored(found))) {
    const ov = await fromOpenverse(sound.query, kind === "bed");
    const k = typeof ov === "string" && fromKenney(sound.query);
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
  const { filled, said, why } = await find(kind, sound);
  if (filled) {
    console.log(`sound ${sound.event ?? "bed"}: ${said}`);
    return filled;
  }
  const event = sound.event ?? "bed";
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
if (dropped.length) kit.dropped = [...(kit.dropped ?? []), ...dropped];
for (const d of dropped)
  console.log(`warn dropped sound: ${d.event}: ${d.why}`);
fs.mkdirSync(store, { recursive: true });
fs.writeFileSync(recordFile, JSON.stringify(records, null, 2) + "\n");
fs.writeFileSync(path.join(run, SOUND), JSON.stringify(kit, null, 2) + "\n");

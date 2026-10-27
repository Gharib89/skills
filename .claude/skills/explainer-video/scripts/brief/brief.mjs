// The brief: the steering prompt's values laid over the run's last brief, or
// over the defaults when there is none, one value per knob plus the
// must-include and avoid lists.
//
//   node brief.mjs <run-folder> [<knob>=<value>]...
//
// Knobs: focus, length (minutes, 1 or more), audience, language, style, voice
// (a narrator id, or `own:<name>` for an own voice enrolled with
// voice/own-voice.mjs, Arabic only), aspect, score (on, off or ace-step); `must=` and `avoid=`
// add one list item each, and any given replaces that list (`must=` alone
// empties it).
// stdout: `brief <knob>: <value>` per knob, then `brief: written -> brief.json`
//         for a new brief, `brief: unchanged`, or `brief: <knobs> changed:
//         redo <stages>`: the first stage those knobs feed and every stage
//         after it, since each stage feeds the next
// writes: <run>/brief.json; a language, voice or style change removes
//         <run>/script.json, since the compiled script carries all three, and
//         a change the script stage redoes removes <run>/check.json, so the
//         new script's support fix attempts count from none
// exit:   0 written · 1 a value this version cannot make, `brief <knob>
//         <value>: <why>` on stderr · 2 usage
import fs from "node:fs";
import path from "node:path";
import { OWN_PREFIX, narrator, narrators } from "../lib/narrators.mjs";
import { maybeJson } from "../lib/json.mjs";
import { explainersDir } from "../lib/runfolder.mjs";
import { stage } from "../lib/stage.mjs";
import { defaultStyle, stores } from "../lib/style.mjs";
import { loadBackend, unavailable } from "../lib/tools.mjs";
import { ASPECTS, SCORES } from "./knobs.mjs";

const KNOBS = [
  "focus",
  "length",
  "audience",
  "language",
  "style",
  "voice",
  "aspect",
  "score",
];
const LISTS = ["must", "avoid"];
// The stages in run order, and the first one each knob feeds.
const STAGES = ["source", "script", "voice", "render"];
const FEEDS = {
  focus: "source",
  length: "source",
  audience: "script",
  language: "script",
  style: "render",
  voice: "script",
  aspect: "render",
  score: "render",
  must: "script",
  avoid: "script",
};

stage("brief");
const [run, ...args] = process.argv.slice(2);
const usage = () => {
  console.error(
    `usage: node brief.mjs <run-folder> [<knob>=<value>]...\n  knobs: ${[...KNOBS, ...LISTS].join(", ")}`,
  );
  process.exit(2);
};
if (!run) usage();

const file = path.join(run, "brief.json");
const old = maybeJson(run, "brief.json");
const given = {};
const lists = {};
for (const a of args) {
  const m = a.match(/^([a-z]+)=(.*)$/s);
  if (!m || ![...KNOBS, ...LISTS].includes(m[1])) usage();
  if (LISTS.includes(m[1]))
    (lists[m[1]] ??= []).push(...(m[2].trim() ? [m[2].trim()] : []));
  else given[m[1]] = m[2].trim();
}
// A narrator kept from the last brief only while it speaks the language.
if (
  !("voice" in given) &&
  old &&
  (given.language ?? old.language) === old.language
)
  given.voice = old.voice;

function refuse(knob, value, why) {
  console.error(
    `brief ${knob}${value === undefined ? "" : ` ${value}`}: ${why}`,
  );
  process.exit(1);
}

const all = narrators();
const styles = stores(explainersDir(run));

const brief = {
  focus: given.focus ?? old?.focus ?? "the source's main ideas",
  length: given.length ?? old?.length ?? 2,
  audience: given.audience ?? old?.audience ?? "a developer new to the source",
  language: given.language ?? old?.language ?? "en",
  style: given.style ?? old?.style ?? defaultStyle(styles),
  voice: given.voice,
  aspect: given.aspect ?? old?.aspect ?? "16:9",
  score: given.score ?? old?.score ?? "on",
  must: lists.must ?? old?.must ?? [],
  avoid: lists.avoid ?? old?.avoid ?? [],
};

for (const k of ["focus", "audience"])
  if (!brief[k]) refuse(k, undefined, "empty");
const minutes = Number(brief.length);
if (!(Number.isFinite(minutes) && minutes >= 1))
  refuse("length", brief.length, "a number of minutes, 1 or more");
brief.length = minutes;
const speakers = all.filter((n) => n.language === brief.language);
if (!speakers.length)
  refuse(
    "language",
    brief.language,
    `no narrator speaks ${brief.language} (${[...new Set(all.map((n) => n.language))].join(", ")})`,
  );
brief.voice ??= speakers.find((n) => n.default).id;
if (!narrator(brief.voice, brief.language))
  refuse(
    "voice",
    brief.voice,
    `no ${brief.language} narrator (${speakers.map((n) => n.id).join(", ")}${brief.language === "ar" ? " or own:<name> for an enrolled own voice" : ""})`,
  );
// The run keeps the profile it copied even after a store drops it.
const own = path.join(run, "style.json");
const held =
  fs.existsSync(own) &&
  JSON.parse(fs.readFileSync(own, "utf8")).name === brief.style;
if (
  !held &&
  !styles.some((d) => fs.existsSync(path.join(d, `${brief.style}.json`)))
)
  refuse(
    "style",
    brief.style,
    `no style profile ${brief.style} in ${styles.join(", ")}`,
  );
if (!ASPECTS.includes(brief.aspect))
  refuse("aspect", brief.aspect, "this version renders 16:9 only");
if (!SCORES.includes(brief.score))
  refuse("score", brief.score, "on, off or ace-step");
// Refuse a knob that names a setup row setup refuses on this machine.
for (const [knob, id] of [
  ["voice", brief.voice.startsWith(OWN_PREFIX) && "own-voice"],
  ["score", brief.score === "ace-step" && "ace-step"],
]) {
  if (!id) continue;
  const why = unavailable(id, (await loadBackend()).platform());
  if (why) refuse(knob, brief[knob], why);
}

for (const k of KNOBS)
  console.log(`brief ${k}: ${brief[k]}${k === "length" ? " min" : ""}`);
for (const k of LISTS)
  console.log(`brief ${k}: ${brief[k].join("; ") || "none"}`);

const changed = old
  ? [...KNOBS, ...LISTS].filter(
      (k) => JSON.stringify(old[k]) !== JSON.stringify(brief[k]),
    )
  : null;
// A new video's brief is the first stage to write its run folder.
fs.mkdirSync(run, { recursive: true });
fs.writeFileSync(file, JSON.stringify(brief, null, 2) + "\n");
if (!changed) console.log("brief: written -> brief.json");
else if (!changed.length) console.log("brief: unchanged");
else {
  // The compiled script carries the language, narrator and style, and the
  // script gates' fix attempts belong to the script being rewritten.
  if (changed.some((k) => ["language", "voice", "style"].includes(k)))
    fs.rmSync(path.join(run, "script.json"), { force: true });
  const redo = STAGES.slice(
    Math.min(...changed.map((k) => STAGES.indexOf(FEEDS[k]))),
  );
  if (redo.includes("script"))
    fs.rmSync(path.join(run, "check.json"), { force: true });
  console.log(`brief: ${changed.join(", ")} changed: redo ${redo.join(", ")}`);
}

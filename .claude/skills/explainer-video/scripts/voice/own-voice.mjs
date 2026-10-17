// Own voice enrollment: a clip of the user's own voice and the consent record
// that lets the voice stage speak in it (Arabic narration, `own:<name>`).
//
//   node own-voice.mjs enroll <name> <clip> --gender female|male --consent "<statement>"
//   node own-voice.mjs remove <name>
//
// <name> is lowercase letters, digits and hyphens. <clip> is any audio ffmpeg
// reads, 8 to 30 s of one speaker; enrolling a name again replaces it.
// stdout: one line, the enrollment or the removal
// writes: <data>/voices/<name>/clip.wav (16-bit PCM, 24 kHz, mono) and
//         consent.json { name, gender, statement, date, clip: sha256 of
//         clip.wav, seconds }; remove deletes the folder
// stderr: a clip outside 8 to 30 s is refused and nothing is kept; enrolling
//         where setup refuses the own-voice row, before anything is written;
//         removing a name nobody enrolled
// exit:   0 done · 1 refused · 2 usage
import fs from "node:fs";
import path from "node:path";
import { clipHash, OWN_NAME, ownVoiceDir } from "../lib/narrators.mjs";
import { loadBackend, unavailable } from "../lib/tools.mjs";

const usage =
  'usage: node own-voice.mjs enroll <name> <clip> --gender female|male --consent "<statement>"\n       node own-voice.mjs remove <name>';
const fail = (message, code) => {
  console.error(message);
  process.exit(code);
};

const [mode, name, ...rest] = process.argv.slice(2);
if (!OWN_NAME.test(name ?? "")) fail(usage, 2);
const dir = ownVoiceDir(name);

if (mode === "remove" && !rest.length) {
  if (!fs.existsSync(dir)) fail(`own-voice: no enrolled voice ${name}`, 1);
  fs.rmSync(dir, { recursive: true, force: true });
  console.log(`own-voice ${name}: removed clip and consent record`);
  process.exit(0);
}

const [input, ...flags] = rest;
const flag = (f) =>
  flags.length === 4 && flags.filter((x) => x === f).length === 1
    ? flags[flags.indexOf(f) + 1]
    : undefined;
const gender = flag("--gender");
const statement = flag("--consent");
if (
  mode !== "enroll" ||
  !input ||
  !["female", "male"].includes(gender) ||
  !statement
)
  fail(usage, 2);

// Seconds in the WAV's data chunk, which ffmpeg may follow a LIST chunk with.
function seconds(file) {
  const b = fs.readFileSync(file);
  let at = 12;
  while (b.toString("ascii", at, at + 4) !== "data")
    at += 8 + b.readUInt32LE(at + 4) + (b.readUInt32LE(at + 4) & 1);
  return +(b.readUInt32LE(at + 4) / 2 / b.readUInt32LE(24)).toFixed(1);
}

const backend = await loadBackend();
// Where setup refuses the own-voice row, an enrolled voice could never speak.
const why = unavailable("own-voice", backend.platform());
if (why) fail(`own-voice: ${why}`, 1);
fs.mkdirSync(dir, { recursive: true });
const part = path.join(dir, "clip.wav.part");
// A refusal leaves nothing behind but an earlier enrollment of the name.
const tidy = () => {
  fs.rmSync(part, { force: true });
  if (!fs.readdirSync(dir).length) fs.rmdirSync(dir);
};
try {
  await backend.voiceClip(input, part);
  const s = seconds(part);
  if (s < 8 || s > 30) {
    tidy();
    fail(`own-voice: the clip is ${s} s; enroll 8 to 30 s of one speaker`, 1);
  }
  fs.renameSync(part, path.join(dir, "clip.wav"));
  fs.writeFileSync(
    path.join(dir, "consent.json"),
    JSON.stringify(
      {
        name,
        gender,
        statement,
        date: new Date().toISOString(),
        clip: clipHash(path.join(dir, "clip.wav")),
        seconds: s,
      },
      null,
      2,
    ) + "\n",
  );
  console.log(
    `own-voice ${name}: enrolled ${s} s, 24 kHz mono, consent recorded at ${dir}`,
  );
} catch (e) {
  tidy();
  fail(`own-voice: ${e.message}`, 1);
}

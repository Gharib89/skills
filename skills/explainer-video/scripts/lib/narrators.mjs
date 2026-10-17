// The narrators a brief, a script and setup name: narrators.json's list, and
// the own voices enrolled in the user data store (voice/own-voice.mjs).
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { userDirs } from "./paths.mjs";
import { skill } from "./tools.mjs";

// An own voice is named `own:<name>`, the name matching OWN_NAME.
export const OWN_PREFIX = "own:";
export const OWN_NAME = /^[a-z0-9][a-z0-9-]*$/;

export const narrators = () =>
  JSON.parse(fs.readFileSync(path.join(skill, "narrators.json"), "utf8"))
    .narrators;

// The sha256 a consent record holds for its clip.
export const clipHash = (file) =>
  crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");

export const ownVoiceDir = (name, dirs = userDirs()) =>
  path.join(dirs.data, "voices", name);

// The narrator `id` names for `language`, or the language's first default when
// id is undefined; null when none. `own:<name>` names an enrolled own voice
// (Arabic only): it speaks through the default Arabic narrator of the enrolled
// gender, converted to the clip. With no clip, no consent record, or a clip
// other than the one the record was given for, there is no such narrator.
export function narrator(id, language) {
  const all = narrators();
  if (!id?.startsWith(OWN_PREFIX))
    return (
      all.find(
        (n) => n.language === language && (id ? n.id === id : n.default),
      ) ?? null
    );
  const name = id.slice(OWN_PREFIX.length);
  if (language !== "ar" || !OWN_NAME.test(name)) return null;
  const dir = ownVoiceDir(name);
  const clip = path.join(dir, "clip.wav");
  const record = path.join(dir, "consent.json");
  if (!fs.existsSync(clip) || !fs.existsSync(record)) return null;
  const consent = JSON.parse(fs.readFileSync(record, "utf8"));
  const hash = clipHash(clip);
  if (hash !== consent.clip) return null;
  const base = all.find(
    (n) => n.language === "ar" && n.default && n.gender === consent.gender,
  );
  if (!base) return null;
  return {
    id,
    language,
    gender: consent.gender,
    backend: "own",
    voice: null,
    style: null,
    licence: base.licence,
    leavesMachine: true,
    rate: base.rate,
    pause: base.pause,
    default: false,
    base,
    clip,
    clipHash: hash,
  };
}

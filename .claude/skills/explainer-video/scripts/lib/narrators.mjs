// The narrators a brief, a script and setup name: narrators.json's list, and
// the own voices enrolled in the user data store (voice/own-voice.mjs).
import fs from "node:fs";
import path from "node:path";
import { userDirs } from "./paths.mjs";
import { skill } from "./tools.mjs";

// An own voice is named `own:<name>`, the name matching OWN_NAME.
export const OWN = "own:";
export const OWN_NAME = /^[a-z0-9][a-z0-9-]*$/;

export const narrators = () =>
  JSON.parse(fs.readFileSync(path.join(skill, "narrators.json"), "utf8"))
    .narrators;

export const ownVoiceDir = (name, dirs = userDirs()) =>
  path.join(dirs.data, "voices", name);

// The narrator `id` names for `language`, or the language's first default when
// id is undefined; null when none. `own:<name>` names an enrolled own voice
// (Arabic only): it speaks through the default Arabic narrator of the enrolled
// gender, converted to the clip. With no clip or no consent record there is no
// such narrator.
export function narrator(id, language) {
  const all = narrators();
  if (!id?.startsWith(OWN))
    return (
      all.find(
        (n) => n.language === language && (id ? n.id === id : n.default),
      ) ?? null
    );
  const name = id.slice(OWN.length);
  if (language !== "ar" || !OWN_NAME.test(name)) return null;
  const dir = ownVoiceDir(name);
  const clip = path.join(dir, "clip.wav");
  const record = path.join(dir, "consent.json");
  if (!fs.existsSync(clip) || !fs.existsSync(record)) return null;
  const consent = JSON.parse(fs.readFileSync(record, "utf8"));
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
    default: false,
    base,
    clip,
    clipHash: consent.clip,
  };
}

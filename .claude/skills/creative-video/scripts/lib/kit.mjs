// The parts of a run's format kit (<run>/project/kit/) the stages read as data:
// cast.json, each role's voice per language and the style it speaks in, and
// sound.json, the bed and the sound palette.
import { maybeJson } from "./json.mjs";
import { narrator as findNarrator } from "./narrators.mjs";

export const CAST = "project/kit/cast.json";
export const SOUND = "project/kit/sound.json";

// sound.json, or null when the run has none.
export const soundKit = (run) => maybeJson(run, SOUND);

// The kit's sounds, the bed first as the event `bed`.
export const kitSounds = (kit) => [
  ...(kit?.bed ? [{ event: "bed", ...kit.bed }] : []),
  ...(kit?.palette ?? []),
];

// A scene's role per sentence: its `roles` entry, `narrator` where the list
// or the entry is missing.
export const rolesOf = (scene) =>
  scene.narration.map((_, i) => scene.roles?.[i] ?? "narrator");

// The narrators.json entry `role` speaks in `language`, cast.json's `style`
// replacing the entry's.
function castVoice(role, { voices, style }, language) {
  const id = voices[language];
  if (!id) throw new Error(`${CAST}: role ${role} has no ${language} voice`);
  const n = findNarrator(id, language);
  if (!n)
    throw new Error(
      `${CAST}: role ${role}'s voice ${id} is no ${language} narrator in narrators.json`,
    );
  return style === undefined ? n : { ...n, style };
}

// The voice of the narrator role and of every role `script` speaks, keyed by
// role, in script.json's language. With no cast.json the video has one voice:
// script.json's `narrator`, else the language's default. With it, a role is
// cast.json's; the narrator role, uncast, keeps that one voice. Throws what
// does not fit: roles not one per sentence, a role the cast lacks, a cast role
// with no narrator in the language.
export function voices(run, script) {
  const cast = maybeJson(run, CAST);
  const { language } = script;
  const out = {
    narrator: cast?.narrator
      ? castVoice("narrator", cast.narrator, language)
      : findNarrator(script.narrator, language),
  };
  if (!out.narrator)
    throw new Error(
      `no narrator ${script.narrator ?? "default"} for ${language}`,
    );
  for (const s of script.scenes) {
    if (s.roles && s.roles.length !== s.narration.length)
      throw new Error(
        `script.json: scene ${s.id} has ${s.narration.length} sentence(s), ${s.roles.length} role(s)`,
      );
    for (const role of rolesOf(s)) {
      if (out[role]) continue;
      if (!cast?.[role])
        throw new Error(
          `script.json: scene ${s.id} names role ${role}, ${cast ? `which ${CAST} does not cast` : `and ${CAST} is missing`}`,
        );
      out[role] = castVoice(role, cast[role], language);
    }
  }
  return out;
}

// voice.json's record of `voices(...)`: each role's narrator id and style, by
// which timing knows the voice stage voiced this cast.
export const voicesOf = (cast) =>
  Object.fromEntries(
    Object.entries(cast).map(([role, n]) => [
      role,
      { narrator: n.id, style: n.style },
    ]),
  );

// The voices `voiced` (voice.json) records, by role: each role some sentence
// speaks, as its narrators.json entry with the style it was voiced in. Not
// cast.json's, which can be edited since, nor an unspoken narrator role.
export function voicedCast(voiced) {
  const spoken = new Set(voiced.scenes.flatMap((s) => s.roles));
  return Object.fromEntries(
    Object.entries(voiced.voices)
      .filter(([role]) => spoken.has(role))
      .map(([role, v]) => [
        role,
        { ...findNarrator(v.narrator, voiced.language), style: v.style },
      ]),
  );
}

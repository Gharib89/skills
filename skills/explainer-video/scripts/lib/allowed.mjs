// What a style profile lets a scene name: its component, its `seam` and its
// `camera` key, each refused with the reason. Compile checks a scene against the
// profile it saw; render checks it again, since the profile may have changed
// between the two.
import { techniquesIn } from "./fragment.mjs";
import { SEAM_MOVES, grammar } from "./style.mjs";
import { TECHNIQUES } from "./visuals.mjs";

// Why `bans` bar a scene's component, or null: it is named, or it uses a
// technique that is. A custom scene uses the techniques its `fragment`'s text
// matches (lib/fragment.mjs), since no list of components says what it draws.
export function banReason(bans, component, name, fragment) {
  if (bans.includes(component))
    return `component ${component} is banned by style profile ${name}`;
  const used = component === "custom" && fragment ? techniquesIn(fragment) : [];
  const technique = Object.keys(TECHNIQUES).find(
    (t) =>
      bans.includes(t) &&
      (TECHNIQUES[t].includes(component) || used.includes(t)),
  );
  return technique
    ? `component ${component} uses ${technique}, which style profile ${name} bans`
    : null;
}

// Why a scene's `seam` is not the profile's to draw, or null: it is neither a
// move of the profile's seams family nor `cut`, a plain cut.
export function seamReason(profile, seam) {
  const { family } = grammar(profile).seams;
  const moves = [...(SEAM_MOVES[family] ?? []), "cut"];
  return seam === undefined || moves.includes(seam)
    ? null
    : `seam ${seam} is not one of ${moves.join(", ")}: the moves of style profile ${profile.name}'s seams family ${family}, and a plain cut`;
}

// Why a scene's `camera` key is not the profile's to draw, or null: the
// profile bans `camera`, or its camera family is locked and draws no push-in.
export function cameraReason(profile, visual) {
  if (visual.camera === undefined) return null;
  const { bans, camera } = grammar(profile);
  if (bans.includes("camera"))
    return `camera is banned by style profile ${profile.name}`;
  return camera.family === "push"
    ? null
    : `camera key needs the push family: style profile ${profile.name}'s camera family is ${camera.family}`;
}

// A scene whose component the profile bans, or whose `seam` or `camera` it
// does not draw, is refused.
export function checkScenes(profile, scenes) {
  const { bans } = grammar(profile);
  for (const s of scenes) {
    const why =
      banReason(
        bans,
        s.visual.component,
        profile.name,
        s.visual.props?.source,
      ) ??
      seamReason(profile, s.visual.seam) ??
      cameraReason(profile, s.visual);
    if (why) throw new Error(`scene ${s.id}: ${why}`);
  }
}

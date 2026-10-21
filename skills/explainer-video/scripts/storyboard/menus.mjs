// The menus on a storyboard card, built from the scene and the profile so the
// page hardcodes no option: the scene's component, camera beat, emphasised item
// and seam, each `{ pick, options[, disabled] }`. A menu that cannot change on
// this card is `disabled` with its one value as the only option.
import { banReason, cameraReason } from "../lib/allowed.mjs";
import { findPhrase } from "../lib/props.mjs";
import { SEAM_MOVES, grammar } from "../lib/style.mjs";
import { VISUALS, cameraCue } from "../lib/visuals.mjs";

// The prop of each row that `emphasis` names its target by, per component
// that takes one over a list of rows.
export const EMPHASIS_TEXT = {
  cards: "label",
  terminal: "text",
  flow: "label",
  panels: "title",
  list: "text",
};

// A cue as a menu value: its sentence number, then the phrase when it has one.
export const cueValue = ({ at, on }) =>
  on === undefined ? `${at}` : `${at} ${on}`;
// The cue a menu value names.
export function cueOf(value) {
  const [, at, on] = value.match(/^(\d+)(?: (.+))?$/s) ?? [];
  return on === undefined ? { at: Number(at) } : { at: Number(at), on };
}

const lockedMenu = (pick) => ({ pick, options: [pick], disabled: true });

function camera(scene, profile) {
  const { visual, narration } = scene;
  const v = VISUALS[visual.component];
  if (v.ownCamera || cameraReason(profile, { camera: {} }) !== null)
    return lockedMenu("none");
  const pick = cameraCue(visual, narration);
  const cues = new Map(
    [
      ...v.items(visual.props ?? {}).map(([, at, , on]) => ({ at, on })),
      pick,
    ].map((c) => [cueValue(c), c]),
  );
  const place = ({ at, on }) =>
    at * 1000 + (on === undefined ? 0 : findPhrase(narration[at - 1], on));
  return {
    pick: cueValue(pick),
    options: [...cues]
      .sort(([, a], [, b]) => place(a) - place(b))
      .map(([value]) => value),
  };
}

// The menu value that names no emphasis: `none`, unless an item is labelled so.
const noEmphasis = (texts) => {
  let off = "none";
  while (texts.includes(off)) off = `(${off})`;
  return off;
};

function emphasis({ visual }) {
  const props = visual.props ?? {};
  const field = EMPHASIS_TEXT[visual.component];
  if (!field) {
    // A code emphasis is a line range and an excerpt's a sentence's text; a
    // note changes either.
    const target = props.emphasis?.target;
    return lockedMenu(
      Array.isArray(target)
        ? `lines ${target[0]}-${target[1]}`
        : (target ?? "none"),
    );
  }
  const texts = props[VISUALS[visual.component].rows].map((x) => x[field]);
  const off = noEmphasis(texts);
  return {
    pick: props.emphasis?.target ?? off,
    // A label two items share names none of them: compile refuses it.
    options: [
      off,
      ...texts.filter((t) => texts.filter((u) => u === t).length === 1),
    ],
  };
}

// `out` is the seam out of the scene the plan drew: a move, or null for a plain
// cut; the last scene has none to pick.
function seam(family, out, last) {
  if (last) return lockedMenu("cut");
  return {
    pick: out?.move ?? "cut",
    options: [...(SEAM_MOVES[family] ?? []), "cut"],
  };
}

// A pick written into a scene's visual: the seam, the camera beat or the
// emphasised item (which lands with its own item). A component pick is not
// written, since each component's props differ and Claude rebuilds the scene.
export function applyPick(visual, menu, value) {
  if (menu === "seam") visual.seam = value;
  else if (menu === "camera") visual.camera = cueOf(value);
  else if (menu === "emphasis") {
    const { props } = visual;
    const rows = props[VISUALS[visual.component].rows];
    const field = EMPHASIS_TEXT[visual.component];
    if (value === noEmphasis(rows.map((x) => x[field]))) delete props.emphasis;
    else {
      const row = rows.find((x) => x[field] === value);
      props.emphasis = {
        target: value,
        at: row.at,
        ...(row.on !== undefined && { on: row.on }),
      };
    }
  } else return false;
  return true;
}

export function cardMenus(scene, profile, out, last) {
  const { bans, seams } = grammar(profile);
  return {
    component: {
      pick: scene.visual.component,
      options: [
        ...Object.keys(VISUALS).filter(
          (c) => !banReason(bans, c, profile.name),
        ),
      ],
    },
    camera: camera(scene, profile),
    emphasis: emphasis(scene),
    seam: seam(seams.family, out, last),
  };
}

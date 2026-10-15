// Style profiles: one JSON file each, looked up in three stores, project first:
// `explainers/.styles/`, the user config store's `styles/`, then the bundled
// `styles/`. A store's `default` file names its default profile; with none
// named anywhere the run takes `claude-code`. Every profile is checked for
// contrast by role when it loads, and a failure refuses the run.
import fs from "node:fs";
import path from "node:path";
import { userDirs } from "./paths.mjs";
import { skill } from "./tools.mjs";

export const FALLBACK = "claude-code";

// The skill's contrast floors (WCAG 2.1); a profile's `gates.contrast` may only
// raise them. Body text sits on every surface; large or faint text (captions
// before their word, accents, status colours) never on the label chip.
const FLOORS = { body: 4.5, large: 3 };
const ROLES = [
  { floor: "body", tokens: ["text", "muted"], on: ["bg", "panel", "chip"] },
  {
    floor: "large",
    tokens: ["faint", "accent", "ok", "warn", "stop"],
    on: ["bg", "panel"],
  },
];

function luminance(hex) {
  const [r, g, b] = [1, 3, 5].map((i) => {
    const v = parseInt(hex.slice(i, i + 2), 16) / 255;
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

export function contrast(a, b) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

// Every token pair below its role's floor, as `<token> on <surface> <ratio>:1,
// floor <n>:1`.
function failures(profile) {
  const c = profile.colors ?? {};
  const out = [];
  for (const role of ROLES) {
    const own = profile.gates?.contrast?.[role.floor];
    if (own !== undefined && !Number.isFinite(own)) {
      out.push(`gates.contrast.${role.floor}: not a number`);
      continue;
    }
    const floor = Math.max(FLOORS[role.floor], own ?? 0);
    for (const t of role.tokens)
      for (const s of role.on) {
        if (
          !/^#[0-9a-f]{6}$/i.test(c[t] ?? "") ||
          !/^#[0-9a-f]{6}$/i.test(c[s] ?? "")
        ) {
          out.push(`${t} on ${s}: not a #rrggbb colour`);
          continue;
        }
        const r = contrast(c[t], c[s]);
        if (r < floor)
          out.push(`${t} on ${s} ${r.toFixed(2)}:1, floor ${floor}:1`);
      }
  }
  return out;
}

export function stores(explainers, dirs = userDirs()) {
  return [
    path.join(explainers, ".styles"),
    path.join(dirs.config, "styles"),
    path.join(skill, "styles"),
  ];
}

const read = (f) =>
  fs.existsSync(f) ? fs.readFileSync(f, "utf8").trim() || null : null;

// The profile a run uses: `<run>/style.json` when the run already holds the
// one it asks for, else the named or default profile from the stores, copied
// into the run so a later edit to the store never changes this video.
export function loadStyle(run, name, dirs = userDirs()) {
  const own = path.join(run, "style.json");
  let profile = fs.existsSync(own)
    ? JSON.parse(fs.readFileSync(own, "utf8"))
    : null;
  if (!profile || (name && profile.name !== name)) {
    const list = stores(path.dirname(path.resolve(run)), dirs);
    const want =
      name ??
      list.map((d) => read(path.join(d, "default"))).find(Boolean) ??
      FALLBACK;
    const file = list
      .map((d) => path.join(d, `${want}.json`))
      .find((f) => fs.existsSync(f));
    if (!file)
      throw new Error(`no style profile ${want} in ${list.join(", ")}`);
    profile = JSON.parse(fs.readFileSync(file, "utf8"));
    profile.name = want;
  }
  const bad = failures(profile);
  if (bad.length)
    throw new Error(
      `style profile ${profile.name} fails contrast: ${bad.join("; ")}`,
    );
  fs.writeFileSync(own, JSON.stringify(profile, null, 2) + "\n");
  return profile;
}

// The closed values the brief's knobs take: brief.mjs refuses any other, and the
// storyboard board offers them as menus, so one list serves both.
import fs from "node:fs";
import path from "node:path";
import { narrators } from "../lib/narrators.mjs";
import { stores } from "../lib/style.mjs";

export const SCORES = ["on", "off", "ace-step"];
export const ASPECTS = ["16:9"];

const names = (dir) =>
  fs.existsSync(dir)
    ? fs
        .readdirSync(dir)
        .filter((f) => f.endsWith(".json"))
        .map((f) => f.slice(0, -".json".length))
    : [];

// The narrators of each language the skill voices, in narrators.json's order.
export function voices() {
  const out = [];
  for (const n of narrators()) {
    let l = out.find((x) => x.language === n.language);
    if (!l) out.push((l = { language: n.language, options: [] }));
    l.options.push(n.id);
  }
  return out;
}

// What the board offers for a brief knob: `menu` with its `options`, `number`
// (length, in minutes) or `text`. The voice menu lists the brief's language's
// narrators; the board's `voices` hold each language's.
export function knobOffer(knob, run, brief) {
  switch (knob) {
    case "length":
      return { type: "number" };
    case "language":
      return { type: "menu", options: voices().map((v) => v.language) };
    case "style": {
      const held = path.join(run, "style.json");
      const styles = new Set(
        stores(path.dirname(path.resolve(run))).flatMap(names),
      );
      if (fs.existsSync(held))
        styles.add(JSON.parse(fs.readFileSync(held, "utf8")).name);
      return { type: "menu", options: [...styles].sort() };
    }
    case "voice":
      return {
        type: "menu",
        options:
          voices().find((v) => v.language === brief.language)?.options ?? [],
      };
    case "aspect":
      return { type: "menu", options: ASPECTS };
    case "score":
      return { type: "menu", options: SCORES };
    default:
      return { type: "text" };
  }
}

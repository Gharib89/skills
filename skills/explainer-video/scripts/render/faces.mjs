// The faces and text helpers a scene draws with, from the style profile: the
// font stacks, the line heights and the Latin runs isolated in Arabic.
import { ARABIC } from "../lib/style.mjs";
import { splitLatin } from "../lib/terms.mjs";
import { esc } from "./box.mjs";

export const family = (profile, role) => `"${profile.type[role].font}"`;
const weight = (profile, role) => profile.type[role].weight ?? 400;

// Right to left, the least line height a role's lines take: Arabic marks reach
// further above and below than Latin ones (the owner's pick, #686).
const AR_LH = { title: 1.5, text: 1.6, caption: 1.7 };

// The faces and text helpers a scene draws with. Right to left, titles and
// text take the Arabic roles, the Latin face behind each for a stray Latin
// glyph, and every Latin run (an English term, a number) is an isolated
// `<bdi>` set in the profile's Latin face and kept on one line.
export function faces(profile, dir = "ltr") {
  const rtl = dir === "rtl";
  const stack = (r) =>
    rtl
      ? `${family(profile, ARABIC[r])}, ${family(profile, r)}`
      : family(profile, r);
  const wrap = (cls) => (s) =>
    rtl
      ? splitLatin(String(s))
          .map((p, i) =>
            i % 2 ? `<bdi class="${cls}">${esc(p)}</bdi>` : esc(p),
          )
          .join("")
      : esc(s);
  return {
    rtl,
    text: stack("text"),
    title: stack("title"),
    titleWeight: weight(profile, rtl ? ARABIC.title : "title"),
    code: family(profile, "code"),
    // A card's or a flow step's note: the code face, which draws no Arabic.
    note: rtl ? stack("text") : family(profile, "code"),
    t: wrap("lat"),
    tt: wrap("lat ti"),
    lh: (v, role) => (rtl ? Math.max(v, AR_LH[role]) : v),
    // Spacing letters apart breaks the joins of Arabic script.
    ls: (v) => (rtl ? "0" : v),
  };
}

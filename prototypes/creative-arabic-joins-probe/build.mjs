// Writes one HyperFrames composition per Arabic face: every sentence set in
// every split style, each unit animated by a paused GSAP timeline. Also writes
// truth.json: per box and word, whether the split changes the word's letter
// shapes by Arabic's joining rules (the rule oracle, independent of any gate).
import fs from "node:fs";

export const FONTS = {
  "noto-sans": {
    family: "Noto Sans Arabic",
    file: "/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf",
  },
  "noto-naskh": {
    family: "Noto Naskh Arabic",
    file: "/usr/share/fonts/truetype/noto/NotoNaskhArabic-Regular.ttf",
  },
  "noto-kufi": {
    family: "Noto Kufi Arabic",
    file: "/usr/share/fonts/truetype/noto/NotoKufiArabic-Regular.ttf",
  },
  "noto-nastaliq": {
    family: "Noto Nastaliq Urdu",
    file: "/usr/share/fonts/truetype/noto/NotoNastaliqUrdu-Regular.ttf",
  },
  plex: {
    family: "IBM Plex Sans Arabic",
    file: "/usr/share/fonts/truetype/ibm-plex/IBMPlexSansArabic-Regular.ttf",
  },
  amiri: {
    family: "Amiri",
    file: "fonts/Amiri-Regular.ttf",
    url: "../../fonts/Amiri-Regular.ttf",
  },
  cairo: {
    family: "Cairo",
    file: "fonts/Cairo.ttf",
    url: "../../fonts/Cairo.ttf",
  },
  tajawal: {
    family: "Tajawal",
    file: "fonts/Tajawal-Regular.ttf",
    url: "../../fonts/Tajawal-Regular.ttf",
  },
};

const SENTENCES = [
  "الأداة دي بتشغّل الأوامر من غير ما تسألك",
  "لما تكتب الملف ده، كلود بيقراه الأول",
  "الصلاحيات ثلاث: اسمح، اسأل، ارفض",
  "لا تشغّل الأمر ده على الفرع الرئيسي",
  "السكربت خلص في 12 ثانية بدل 40",
  "افتح ملف CLAUDE.md وشوف القواعد",
  "مُحَمَّدٌ يَكْتُبُ الكُودَ بِسُرْعَةٍ",
  "الذكاء الاصطناعي مش سحر، ده إحصاء",
  "كل مرحلة ليها بوابة بتقيس الفيديو",
  "إزاي نعرف إن الحروف لسه متوصلة؟",
  "الإطار الأول لازم يكون علامة الفصل",
  "ورد دار زاد وراء دوره",
];

// Remotion's arabic-text.md split, verbatim in behaviour.
const ZWJ = "‍";
const RIGHT_JOINING = /[آ-إاةد-زوٱ-ٳٵ-ٷڈ-ڙۀۃ-ۋۍۏےۓە]/;
const LETTER = /[ؠ-يٮ-ۓەۺ-ۼۿ]/;
const LTR_RUN = /^[0-9٠-٩۰-۹A-Za-z٫٬.,:%]+$/;
const MARK = /[ً-ٰٟۖ-ۭ]/;
const MARKS = /[ً-ٰٟۖ-ۭ‍]/g;
const first = (u) => u.replace(MARKS, "")[0] ?? "";
const last = (u) => u.replace(MARKS, "").slice(-1);
const joinsPrev = (u) => LETTER.test(first(u)) && first(u) !== "ء";
const joinsNext = (u) =>
  LETTER.test(last(u)) && last(u) !== "ء" && !RIGHT_JOINING.test(last(u));

export function remotionUnits(text) {
  const g = [];
  for (const ch of text) {
    if (MARK.test(ch) && g.length > 0) g[g.length - 1] += ch;
    else g.push(ch);
  }
  const units = [];
  for (let i = 0; i < g.length; i++) {
    if (LTR_RUN.test(g[i])) {
      let run = g[i];
      while (g[i + 1] && LTR_RUN.test(g[i + 1])) run += g[++i];
      units.push(run);
    } else if (first(g[i]) === "ل" && /[آأإا]/.test(first(g[i + 1] ?? ""))) {
      units.push(g[i] + g[++i]);
    } else units.push(g[i]);
  }
  return units.map((u, i) => {
    const before = i > 0 && joinsNext(units[i - 1]) && joinsPrev(u) ? ZWJ : "";
    const after =
      i < units.length - 1 && joinsNext(u) && joinsPrev(units[i + 1])
        ? ZWJ
        : "";
    return before + u + after;
  });
}

const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;");
const span = (u, cls = "u") =>
  u === " " ? " " : `<span class="${cls}">${esc(u)}</span>`;

// Each style: markup, and the per-word truth: why the split changes the
// word's shapes or order by Arabic's joining rules, or null. Marks count as
// part of their base letter.
function bases(word) {
  const out = [];
  for (const c of word) {
    if (MARK.test(c) && out.length) out[out.length - 1].marks = true;
    else out.push({ c, marks: false });
  }
  return out;
}
const realRight = (b, i) => i > 0 && joinsNext(b[i - 1].c) && joinsPrev(b[i].c);
const realLeft = (b, i) =>
  i < b.length - 1 && joinsNext(b[i].c) && joinsPrev(b[i + 1].c);
const reversed = (word) =>
  /[0-9A-Za-z\u0660-\u0669]{2}|[A-Za-z][.][A-Za-z]/.test(word);
function brokenPlain(word) {
  const b = bases(word);
  if (b.some((x) => x.marks)) return "mark split from its base";
  if (b.some((_, i) => realRight(b, i))) return "join lost";
  if (reversed(word)) return "Latin or digit run reversed";
  return null;
}
function brokenNaive(word) {
  const b = bases(word);
  if (b.some((x) => x.marks)) return "mark split from its base";
  for (let i = 0; i < b.length; i++) {
    const c = b[i].c;
    if (!LETTER.test(c)) continue;
    if (c === "\u0644" && /[\u0622\u0623\u0625\u0627]/.test(b[i + 1]?.c ?? ""))
      return "lam-alef ligature split";
    const forcedRight = i > 0 && joinsPrev(c);
    const forcedLeft = i < b.length - 1 && joinsNext(c);
    if (forcedRight !== realRight(b, i) || forcedLeft !== realLeft(b, i))
      return "joiner forces a join";
  }
  if (reversed(word)) return "Latin or digit run reversed";
  return null;
}

const STYLES = {
  whole: { markup: (t) => esc(t), unit: null, truth: () => null },
  words: {
    markup: (t) =>
      t
        .split(" ")
        .map((w) => span(w))
        .join(" "),
    unit: ".u",
    truth: () => null,
  },
  "words-gap": {
    markup: (t) =>
      t
        .split(" ")
        .map((w) => span(w))
        .join(""),
    unit: ".u",
    truth: () => null,
    gap: true,
  },
  "letters-inline": {
    markup: (t) => [...t].map((c) => span(c, "c")).join(""),
    unit: ".c",
    truth: () => null,
    color: true,
  },
  zwj: {
    markup: (t) =>
      remotionUnits(t)
        .map((u) => span(u))
        .join(""),
    unit: ".u",
    truth: () => null,
  },
  "zwj-naive": {
    markup: (t) =>
      t
        .split(" ")
        .map((w) =>
          [...w]
            .map((c, i, a) =>
              span(
                (i > 0 && LETTER.test(c) ? ZWJ : "") +
                  c +
                  (i < a.length - 1 && LETTER.test(c) ? ZWJ : ""),
              ),
            )
            .join(""),
        )
        .join(" "),
    unit: ".u",
    truth: brokenNaive,
  },
  letters: {
    markup: (t) => [...t].map((c) => span(c)).join(""),
    unit: ".u",
    truth: brokenPlain,
  },
};

export function build() {
  const truth = {};
  for (const [key, font] of Object.entries(FONTS)) {
    const boxes = [];
    let script = "";
    let i = 0;
    for (const [s, text] of SENTENCES.entries())
      for (const [style, def] of Object.entries(STYLES)) {
        const id = `b${i++}`;
        truth[`${key}/${id}`] = {
          font: key,
          style,
          sentence: s,
          words: text.split(" ").map((w) => def.truth(w)),
        };
        boxes.push(
          `<div id="${id}" class="box${def.gap ? " gap" : ""}" dir="rtl" lang="ar" data-style="${style}">${def.markup(text)}</div>`,
        );
        const t0 = (i % 7) * 0.05;
        if (!def.unit)
          script += `tl.fromTo("#${id}", {y: 40, opacity: 0, rotation: 4}, {y: 0, opacity: 1, rotation: 0, duration: 1.6}, ${t0});\n`;
        else if (def.color)
          script += `tl.fromTo("#${id} ${def.unit}", {color: "#e85d3a"}, {color: "#1b1b1b", duration: 0.4, stagger: 0.05}, ${t0});\n`;
        else
          script += `tl.fromTo("#${id} ${def.unit}", {y: 50, opacity: 0, rotation: -25, scale: 0.4}, {y: 0, opacity: 1, rotation: 0, scale: 1, duration: 0.7, stagger: 0.04}, ${t0});\n`;
      }
    const face = font.url
      ? `@font-face { font-family: "${font.family}"; src: url("${font.url}"); }`
      : "";
    const html = `<!doctype html>
<html lang="ar">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=1920, height=1080" />
    <script src="https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js"></script>
    <style>
      ${face}
      * { margin: 0; padding: 0; box-sizing: border-box; }
      html, body { width: 1920px; height: 1080px; overflow: hidden; background: #f4efe6; }
      #root { width: 100%; height: 100%; padding: 24px 60px; font-family: "${font.family}"; color: #1b1b1b; font-size: 44px; line-height: 1.9; }
      .box { width: 1800px; }
      .box .u { display: inline-block; }
      .box.gap { display: flex; gap: 0.35em; }
    </style>
  </head>
  <body>
    <div id="root" data-composition-id="main" data-start="0" data-duration="3" data-width="1920" data-height="1080">
      ${boxes.join("\n      ")}
    </div>
    <script>
      const tl = gsap.timeline({ paused: true });
      ${script}
      window.__timelines = window.__timelines || {};
      window.__timelines["main"] = tl;
      tl.seek(0);
    </script>
  </body>
</html>
`;
    fs.mkdirSync(`comp/${key}`, { recursive: true });
    fs.writeFileSync(`comp/${key}/index.html`, html);
  }
  fs.writeFileSync("truth.json", JSON.stringify(truth, null, 1));
}

if (import.meta.url === `file://${process.argv[1]}`) build();

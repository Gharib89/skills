// The style card: a draft style profile shown on five sample frames (a title,
// a diagram, a caption, a code frame and an Arabic frame) over the shared
// layout, gated by the video gates' layout and contrast rules, then saved to a
// store or used once.
//
//   node card.mjs <run-folder> <draft> build [--local] [--project]
//   node card.mjs <run-folder> <draft> page [<url>]
//   node card.mjs <run-folder> <draft> asset <path>=<url>...
//   node card.mjs <run-folder> <draft> apply <answers-file> [--project]
//
// <draft> names <run>/style-draft/<draft>.json, the draft.mjs output. The
// documents are the contract in storyboard/card-data.md; the files live in
// <run>/style-draft/card/. `build` renders the frames into frames/, measures
// them with HyperFrames' check and the layout probe, and writes the next card
// version <n>.json and the local stylecard.html; with a published page (`page
// <url>`) every font file needs an uploaded URL, recorded by `asset`.
// `page` with no url writes page.html, the file a session publishes once.
// `apply` reads the answers (the answers document, or the text the page
// copies) into answers-<n>.json: edited colours or fonts go into the draft,
// which needs the next version; otherwise Save writes the draft to the user
// store when this copy of the skill is user-scoped, else to the project's
// explainers/.styles/ (`--project` forces the project, and on `build` names
// that store on the card), and Use once writes it to <run>/style.json.
// stdout: build `card <n>: <f> frame(s), <k> finding(s) -> style-draft/card/
//         <n>.json`, then where the page is; apply `card: rebuild`, `card:
//         revise: <note>`, `card: saved <name> -> <file>[, default of the
//         <scope> store]` or `card: once <name> -> style.json`
// writes: <run>/style-draft/card/, the draft, a store's <name>.json and
//         default, <run>/style.json
// exit:   0 ok · 1 refused, `card: <why>` on stderr · 2 usage
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { judge } from "../lib/layout.mjs";
import { userDirs } from "../lib/paths.mjs";
import { recordAssets } from "../lib/runfolder.mjs";
import {
  ARABIC,
  COMPANION,
  ROLES,
  floors,
  saveScope,
  validate,
} from "../lib/style.mjs";
import {
  catalogue,
  compositionAssets,
  dest,
  fontRow,
  hyperframesEnv,
  loadBackend,
  nearest,
  skill,
  weights,
} from "../lib/tools.mjs";
import { esc, framePage, sceneFile, stillsPage } from "../render/compose.mjs";

const [run, draftName, cmd, ...args] = process.argv.slice(2);
const usage = () => {
  console.error(
    "usage: node card.mjs <run-folder> <draft> build [--local] [--project] | page [<url>] | asset <path>=<url>... | apply <answers-file> [--project]",
  );
  process.exit(2);
};
if (
  !run ||
  !draftName ||
  !["build", "page", "asset", "apply"].includes(cmd) ||
  (cmd === "build" &&
    (new Set(args).size < args.length ||
      !args.every((a) => ["--local", "--project"].includes(a)))) ||
  (cmd === "page" && args.length > 1) ||
  (cmd === "asset" && !args.length) ||
  (cmd === "apply" &&
    (args.length < 1 ||
      args.length > 2 ||
      (args[1] && args[1] !== "--project")))
)
  usage();
function fail(why) {
  console.error(`card: ${why}`);
  process.exit(1);
}

const KEBAB = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const LATIN = ["title", "text", "code"];
const ROLE_NAMES = [...LATIN, "arTitle", "arText"];
const draftFile = path.join(run, "style-draft", `${draftName}.json`);
const cardDir = path.join(run, "style-draft", "card");
const at = (...p) => path.join(cardDir, ...p);
const json = (f) => JSON.parse(fs.readFileSync(f, "utf8"));
const maybe = (f) => (fs.existsSync(f) ? json(f) : null);
const write = (f, data) => {
  fs.mkdirSync(path.dirname(f), { recursive: true });
  fs.writeFileSync(f, JSON.stringify(data, null, 2) + "\n");
};
const versions = () =>
  fs.existsSync(cardDir)
    ? fs
        .readdirSync(cardDir)
        .map((f) => f.match(/^(\d+)\.json$/)?.[1])
        .filter(Boolean)
        .map(Number)
        .sort((a, b) => a - b)
    : [];
const template = () =>
  fs.readFileSync(path.join(skill, "storyboard", "card.html"), "utf8");
// The store Save writes to: the user config store's styles/, or the project's
// explainers/.styles/.
const storeOf = (scope) =>
  scope === "user"
    ? path.join(userDirs().config, "styles")
    : path.join(path.dirname(path.resolve(run)), ".styles");
const scope = args.includes("--project")
  ? "project"
  : saveScope(skill, os.homedir());
const store = storeOf(scope);
// The families a role can take: setup's Latin ones, and those the draft
// fetched.
const families = () => [
  ...new Set(
    [...catalogue(), ...(draft.fonts ?? [])]
      .filter((r) => r.kind === "font" && r.language !== "ar")
      .map((r) => r.family),
  ),
];

if (!fs.existsSync(draftFile))
  fail(`no ${draftFile}: run style/draft.mjs first`);
const draft = json(draftFile);
const title = `Style card: ${draft.label ?? draft.name}`;

if (cmd === "page") {
  const [url] = args;
  if (!url) {
    fs.mkdirSync(cardDir, { recursive: true });
    fs.writeFileSync(
      at("page.html"),
      template().replace("{{TITLE}}", () => esc(title)),
    );
    console.log("card: page style-draft/card/page.html");
  } else {
    if (!url.startsWith("https://")) fail(`${url} is not an https:// URL`);
    write(at("page.json"), { url });
    console.log(`card: page ${url} -> style-draft/card/page.json`);
  }
  process.exit(0);
}

// Uploaded media by its path under the run folder, as `build` prints it.
if (cmd === "asset") {
  const file = at("assets.json");
  try {
    write(file, { ...maybe(file), ...recordAssets(run, args) });
  } catch (e) {
    fail(e.message);
  }
  console.log(`card: ${args.length} asset(s) recorded`);
  process.exit(0);
}

if (cmd === "apply") {
  const all = versions();
  if (!all.length) fail("no card yet: run build first");
  const n = all.at(-1);
  const card = json(at(`${n}.json`));
  const raw = fs.readFileSync(args[0], "utf8");
  let a;
  if (raw.trimStart().startsWith("{")) a = JSON.parse(raw);
  else {
    const lines = raw.split("\n");
    const head = lines[0].match(/^explainer-video: style card (\d+) answers/);
    if (!head) fail("not an answers text: its first line is not the header");
    a = { version: Number(head[1]), colors: {}, type: {}, note: "" };
    const CHOICE = { Save: "save", "Use once": "once", Revise: "revise" };
    for (const line of lines.slice(1)) {
      let m;
      if ((m = line.match(/^Choice: (Save|Use once|Revise)$/)))
        a.choice = CHOICE[m[1]];
      else if ((m = line.match(/^Name: (.*)$/))) a.name = m[1];
      else if ((m = line.match(/^Colour (\w+): (.*)$/))) a.colors[m[1]] = m[2];
      else if ((m = line.match(/^Font (\w+): (.*)$/))) a.type[m[1]] = m[2];
      else if (line === "Replace: yes") a.replace = true;
      else if (line === "Default: yes") a.default = true;
      else if ((m = line.match(/^Note: (.*)$/))) a.note = m[1];
      else if (line.trim()) fail(`cannot read this answers line: ${line}`);
    }
  }
  if (a.version !== n)
    fail(`answers for card ${a.version}, the latest is card ${n}`);
  if (!["save", "once", "revise"].includes(a.choice))
    fail("the answers hold no choice");
  if (!KEBAB.test(a.name ?? "")) fail(`name ${a.name} is not kebab-case`);
  const colors = a.colors ?? {};
  const type = a.type ?? {};
  for (const [t, hex] of Object.entries(colors)) {
    if (!(t in draft.colors)) fail(`no colour token ${t}`);
    if (!/^#[0-9a-f]{6}$/i.test(hex))
      fail(`${t} ${hex} is not a #rrggbb colour`);
  }
  for (const [r, font] of Object.entries(type)) {
    // The card offers no Arabic role: each takes its class's companion.
    if (!LATIN.includes(r)) fail(`no type role ${r} on the card`);
    if (!families().includes(font))
      fail(
        `font ${font} for ${r} is not one setup installs or the draft fetched (${families().join(", ")})`,
      );
  }
  write(at(`answers-${n}.json`), {
    version: n,
    submittedAt: a.submittedAt ?? new Date().toISOString(),
    choice: a.choice,
    name: a.name,
    colors,
    type,
    note: a.note ?? "",
    replace: !!a.replace,
    default: !!a.default,
  });

  const edited = Object.keys(colors).length + Object.keys(type).length > 0;
  if (edited) {
    for (const [t, hex] of Object.entries(colors)) {
      draft.marks ??= {};
      draft.marks[t] = {
        mark: "edited",
        was: draft.colors[t],
        why: "edited on the style card",
      };
      draft.colors[t] = hex.toLowerCase();
    }
    // The weight the family holds nearest the role's: a family the draft
    // fetched holds only the weights its roles took.
    for (const [r, font] of Object.entries(type)) {
      draft.type[r] = {
        weight: nearest(draft.type[r]?.weight, weights(fontRow(draft, font))),
        font,
        mark: "edited",
        why: "edited on the style card",
      };
      const ar = ARABIC[r];
      const cls = fontRow(draft, font).class;
      if (ar)
        draft.type[ar] = {
          ...draft.type[ar],
          font: COMPANION[cls],
          mark: "derived",
          why: `the ${cls} companion of ${font}`,
        };
    }
  }
  draft.name = a.name;
  try {
    validate(draft);
  } catch (e) {
    fail(e.message);
  }
  write(draftFile, draft);
  if (edited) {
    console.log("card: rebuild");
    process.exit(0);
  }
  if (a.choice === "revise") {
    console.log(`card: revise: ${a.note || "no note"}`);
    process.exit(0);
  }
  if (card.findings.length)
    fail(
      `card ${n} has ${card.findings.length} finding(s): revise the draft before ${a.choice === "save" ? "saving" : "using"} it`,
    );
  if (a.choice === "once") {
    write(path.join(run, "style.json"), draft);
    console.log(`card: once ${draft.name} -> style.json`);
    process.exit(0);
  }
  const out = path.join(store, `${draft.name}.json`);
  if (fs.existsSync(out) && !a.replace)
    fail(
      `${draft.name} is saved in the ${scope} store already: tick Replace on the card`,
    );
  // A run reads the project store first, so a project profile of this name
  // would hide the one saved here.
  if (
    scope === "user" &&
    fs.existsSync(path.join(storeOf("project"), `${draft.name}.json`))
  )
    fail(
      `the project store holds a ${draft.name} that would hide this one: pick another name`,
    );
  write(out, draft);
  if (a.default)
    fs.writeFileSync(path.join(store, "default"), `${draft.name}\n`);
  console.log(
    `card: saved ${draft.name} -> ${out}${a.default ? `, default of the ${scope} store` : ""}`,
  );
  process.exit(0);
}

// build
let floor;
try {
  validate(draft);
  floor = floors(draft);
} catch (e) {
  fail(e.message);
}
const rows = catalogue();
const fontRows = [...new Set(LATIN.map((r) => draft.type?.[r]?.font))].map(
  (font) =>
    fontRow(draft, font) ??
    fail(`the draft names font ${font}, which no setup row installs`),
);
for (const r of [
  ...rows.filter((r) => ["npm", "chrome"].includes(r.kind)),
  ...fontRows,
])
  if (!fs.existsSync(path.join(dest(r), ".stamp")))
    fail(`${r.id} is not installed: run /explainer-video setup`);

// The sample frames: what a video shows most, each over the header and
// caption bands. The Arabic frame sets its title and text in the Arabic roles,
// right to left.
const label = draft.label ?? draft.name;
const SAMPLES = [
  {
    id: "title",
    label: "Title",
    visual: {
      component: "title",
      props: {
        kicker: "Style card",
        title: label,
        subtitle: "A draft style profile on the shared layout",
      },
    },
  },
  {
    id: "diagram",
    label: "Diagram",
    visual: {
      component: "flow",
      props: {
        steps: [
          { label: "Measure", at: 1 },
          { label: "Assign", at: 1 },
          { label: "Draft", at: 1 },
        ],
      },
    },
  },
  {
    id: "caption",
    label: "Caption",
    cue: "Each word turns the text colour as the narrator says it",
    visual: {
      component: "cards",
      props: {
        items: [
          { label: "Said", value: "Text", at: 1 },
          { label: "Unsaid", value: "Faint", at: 1 },
        ],
      },
    },
  },
  {
    id: "code",
    label: "Code",
    visual: {
      component: "code",
      props: {
        lang: "json",
        file: `${draft.name}.json`,
        code: `{\n  "bg": "${draft.colors.bg}",\n  "accent": "${draft.colors.accent}"\n}`,
        highlights: [{ lines: [3, 3], at: 1 }],
      },
    },
  },
  {
    id: "arabic",
    label: "Arabic",
    dir: "rtl",
    visual: {
      component: "title",
      props: {
        kicker: "بطاقة الأسلوب",
        title: "فيديو شرح",
        subtitle: "ملف أسلوب على التخطيط المشترك",
      },
    },
  },
];
const arabic = {
  ...draft,
  type: { ...draft.type, title: draft.type.arTitle, text: draft.type.arText },
};
const profileOf = (s) => (s.dir === "rtl" ? arabic : draft);

const backend = await loadBackend();
const frames = at("frames");
fs.rmSync(frames, { recursive: true, force: true });
fs.mkdirSync(path.join(frames, "scenes"), { recursive: true });
const fonts = compositionAssets(fontRows, frames);
const timing = { duration: 1, sentences: [0] };
for (const s of SAMPLES)
  fs.writeFileSync(
    path.join(frames, "scenes", `${s.id}.html`),
    await sceneFile(s, timing, profileOf(s), { backend, dir: s.dir }),
  );
fs.writeFileSync(
  path.join(frames, "index.html"),
  stillsPage({
    title: label,
    profile: draft,
    fonts,
    ids: SAMPLES.map((s) => s.id),
    frame: 1,
    cues: Object.fromEntries(
      SAMPLES.filter((s) => s.cue).map((s) => [s.id, s.cue]),
    ),
  }),
);

// The gate: frame i holds second i and is measured mid-way, as HyperFrames'
// seek leaves some clips a frame long unmounted. A frame with no text of its
// own is a probe that saw nothing, not a pass.
const times = SAMPLES.map((_, i) => i + 0.5);
const env = hyperframesEnv();
let checked, probed;
try {
  checked = await backend.check(frames, times, { env });
  if (!checked.layout || !checked.contrast)
    throw new Error(
      `hyperframes check: ${checked.error ?? "no layout or contrast result"}`,
    );
  probed = await backend.probe(frames, times, { env });
} catch (e) {
  fail(e.message);
}
const frameAt = (t) => SAMPLES[Math.min(SAMPLES.length - 1, Math.floor(t))];
for (const s of SAMPLES)
  if (
    !probed.some(
      (f) => frameAt(f.t) === s && f.elements.some((e) => e.scene === s.id),
    )
  )
    fail(`layout probe: no text in frame ${s.id}`);
const findings = [];
judge(checked, probed, floor, (gate, t, what) => {
  const line = `${gate} ${frameAt(t).id}: ${what}`;
  if (!findings.includes(line)) findings.push(line);
});

// What the page shows: each frame as a static page, its fonts by URL.
const pages = [];
for (const s of SAMPLES)
  pages.push({
    id: s.id,
    label: s.label,
    html: await framePage({
      title: label,
      profile: profileOf(s),
      fonts,
      scene: s,
      cue: s.cue,
      backend,
      dir: s.dir,
    }),
  });
const media = fonts.map((f) => `style-draft/card/frames/fonts/${f.file}`);
const page = maybe(at("page.json"));
const published = !!page && args[0] !== "--local";
const assets = maybe(at("assets.json")) ?? {};
if (published && media.some((f) => !assets[f])) {
  for (const f of media.filter((f) => !assets[f]))
    console.error(
      `card: upload ${f} (${(fs.statSync(path.join(run, f)).size / 1e6).toFixed(1)} MB)`,
    );
  fail(
    `record each upload with: node card.mjs ${run} ${draftName} asset <path>=<url>`,
  );
}

const marks = draft.marks ?? {};
const doc = {
  version: (versions().at(-1) ?? 0) + 1,
  name: draft.name,
  label,
  source: draft.source ?? "",
  colors: Object.entries(draft.colors).map(([token, hex]) => ({
    token,
    hex,
    mark: marks[token]?.mark ?? "bundled",
    why: marks[token]?.why ?? "",
  })),
  roles: ROLES.map((r) => ({
    min: floor.contrast[r.floor],
    tokens: r.tokens,
    on: r.on,
  })),
  type: ROLE_NAMES.map((role) => {
    const { font, mark, why } = draft.type[role];
    return { role, font, ...(mark && { mark, why }) };
  }),
  families: families(),
  fonts: fonts.map((f, i) => ({
    file: f.file,
    url: published ? assets[media[i]] : `frames/fonts/${f.file}`,
  })),
  frames: pages,
  findings,
  scope,
  taken: fs.existsSync(store)
    ? fs
        .readdirSync(store)
        .filter((f) => f.endsWith(".json"))
        .map((f) => f.slice(0, -5))
    : [],
};
write(at(`${doc.version}.json`), doc);
// The local copy declares its encoding: no publish wraps it in a skeleton.
fs.writeFileSync(
  at("stylecard.html"),
  '<!doctype html>\n<meta charset="utf-8">\n' +
    template()
      .replace("{{TITLE}}", () => esc(title))
      .replace(
        '<script type="application/json" id="card">null</script>',
        () =>
          `<script type="application/json" id="card">${JSON.stringify({ ...doc, fonts: doc.fonts.map((f) => ({ ...f, url: `frames/fonts/${f.file}` })) }).replaceAll("<", "\\u003c")}</script>`,
      ),
);
console.log(
  `card ${doc.version}: ${SAMPLES.length} frame(s), ${findings.length} finding(s) -> style-draft/card/${doc.version}.json`,
);
for (const f of findings) console.log(`card ${f}`);
console.log(
  published
    ? `card: post style-draft/card/${doc.version}.json to cards/${doc.version}`
    : "card: local page style-draft/card/stylecard.html",
);

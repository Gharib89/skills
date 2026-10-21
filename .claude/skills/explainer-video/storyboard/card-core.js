/* ---- core: state in, HTML out. No DOM here, so the page can run headless against card-data.md. ---- */
const KEBAB = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const HEX = /^#[0-9a-f]{6}$/i;
const CHOICES = [
  ["save", "Save"],
  ["once", "Use once"],
  ["revise", "Revise"],
];
// The roles a card offers fonts for: the catalogue holds Latin families only.
const LATIN = ["title", "text", "code"];

function newState(title) {
  return {
    title,
    cards: [],
    submitted: {},
    drafts: {},
    status: "idle",
    mode: "loading",
    canEdit: true,
    local: false,
    inView: {},
  };
}
const latest = (S) => S.cards[S.cards.length - 1];
function newDraft(c) {
  return {
    choice: null,
    name: c.name,
    note: "",
    replace: false,
    default: false,
    colors: Object.fromEntries(c.colors.map((x) => [x.token, x.hex])),
    type: Object.fromEntries(c.type.map((x) => [x.role, x.font])),
  };
}
function draftOf(S) {
  const c = latest(S);
  if (!S.drafts[c.version]) S.drafts[c.version] = newDraft(c);
  return S.drafts[c.version];
}
function setCards(S, docs) {
  const was = latest(S) && latest(S).version;
  S.cards = docs.slice().sort((a, b) => a.version - b.version);
  S.mode = "ready";
  if (latest(S) && latest(S).version !== was) S.status = "idle";
}
function setAnswers(S, docs) {
  S.submitted = Object.fromEntries(docs.map((d) => [d.version, true]));
}

const locked = (S) =>
  !S.canEdit ||
  ["sending", "sent", "saved"].includes(S.status) ||
  !!S.submitted[latest(S).version];
// A failed save leaves the comment as the only copy, so it counts as sent only when it held the whole answers.
const outcome = (saved, woke, whole) =>
  woke && (saved || whole) ? "sent" : saved ? "saved" : "neither";

// WCAG 2.1 contrast, the same sums as lib/style.mjs.
function luminance(hex) {
  const [r, g, b] = [1, 3, 5].map((i) => {
    const v = parseInt(hex.slice(i, i + 2), 16) / 255;
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
function contrast(a, b) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}
// Every pair the card's roles hold below its floor, with the edited colours.
function failing(S) {
  const c = latest(S),
    d = draftOf(S),
    out = [];
  for (const r of c.roles)
    for (const t of r.tokens)
      for (const s of r.on) {
        if (!HEX.test(d.colors[t] || "") || !HEX.test(d.colors[s] || "")) {
          out.push(`${t} on ${s}: not a #rrggbb colour`);
          continue;
        }
        const x = contrast(d.colors[t], d.colors[s]);
        if (x < r.min)
          out.push(`${t} on ${s} ${x.toFixed(2)}:1, floor ${r.min}:1`);
      }
  return out;
}
function edits(S) {
  const c = latest(S),
    d = draftOf(S);
  return {
    colors: Object.fromEntries(
      c.colors
        .filter((x) => d.colors[x.token].toLowerCase() !== x.hex.toLowerCase())
        .map((x) => [x.token, d.colors[x.token].toLowerCase()]),
    ),
    type: Object.fromEntries(
      c.type
        .filter((x) => d.type[x.role] !== x.font)
        .map((x) => [x.role, d.type[x.role]]),
    ),
  };
}
const edited = (S) => {
  const e = edits(S);
  return Object.keys(e.colors).length + Object.keys(e.type).length > 0;
};
const taken = (S) =>
  draftOf(S).choice === "save" && latest(S).taken.includes(draftOf(S).name);
// Why Submit is off, one line each; none means it is on.
function blockers(S) {
  const c = latest(S),
    d = draftOf(S),
    out = [];
  if (!d.choice) out.push("Pick Save, Use once or Revise.");
  if (!KEBAB.test(d.name))
    out.push(
      "The name is lowercase words joined by hyphens, like itworx-dark.",
    );
  if (failing(S).length)
    out.push("A colour fails contrast: fix it before submitting.");
  if (taken(S) && !d.replace)
    out.push(
      `${d.name} is saved in the ${c.scope} store already: tick Replace, or rename it.`,
    );
  if (c.findings.length && ["save", "once"].includes(d.choice) && !edited(S))
    out.push(
      "The frames break the layout rules: edit the draft or ask for a revision.",
    );
  return out;
}
const canSubmit = (S) => !!latest(S) && !locked(S) && blockers(S).length === 0;

const ACT = {
  color(S, d) {
    if (!locked(S)) draftOf(S).colors[d.token] = d.hex;
  },
  font(S, d) {
    if (!locked(S)) draftOf(S).type[d.role] = d.font;
  },
  set(S, d) {
    if (!locked(S)) draftOf(S)[d.field] = d.value;
  },
};

function answersDoc(S, at = new Date().toISOString()) {
  const d = draftOf(S),
    e = edits(S);
  return {
    version: latest(S).version,
    submittedAt: at,
    choice: d.choice,
    name: d.name.trim(),
    colors: e.colors,
    type: e.type,
    note: d.note.trim(),
    replace: taken(S) && d.replace,
    default: d.choice === "save" && d.default,
  };
}
function answersText(S) {
  const n = latest(S).version,
    a = answersDoc(S);
  // Names the database document without claiming the save worked: this text is also the fallback.
  const lines = [
    `explainer-video: style card ${n} answers (database document answers/card-${n})`,
  ];
  const choice = CHOICES.find((x) => x[0] === a.choice);
  if (choice) lines.push("Choice: " + choice[1]);
  lines.push("Name: " + a.name);
  for (const [t, hex] of Object.entries(a.colors))
    lines.push(`Colour ${t}: ${hex}`);
  for (const [r, f] of Object.entries(a.type)) lines.push(`Font ${r}: ${f}`);
  if (a.replace) lines.push("Replace: yes");
  if (a.default) lines.push("Default: yes");
  if (a.note) lines.push("Note: " + a.note.replace(/\s*\n\s*/g, " "));
  return lines.join("\n");
}

const esc = (s) =>
  String(s == null ? "" : s).replace(
    /[&<>"]/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c],
  );
// A media URL is https, the artifact's own /_blob/, or a path relative to the page; nothing else reaches src.
function mediaUrl(u) {
  const s = String(u == null ? "" : u);
  if (/["'()\\\s]/.test(s)) return "";
  if (/^https:/i.test(s) || s.startsWith("/_blob/")) return s;
  return /^[a-z][a-z0-9+.-]*:/i.test(s) || s.startsWith("/") ? "" : s;
}
// The live build's script URL, or "" when it is not one a page may load.
const buildUrl = (c) => mediaUrl(c.live && c.live.url);
// The edited palette as CSS: the frame's own palette comes first, so this one wins.
const paletteCss = (S) =>
  ":root { " +
  Object.entries(draftOf(S).colors)
    .filter(([, v]) => HEX.test(v))
    .map(([k, v]) => `--${k}: ${v};`)
    .join(" ") +
  " }";
// A frame's page with no script, its fonts at their URLs and the edited palette appended.
function frameDoc(S, f) {
  const urls = Object.fromEntries(
    latest(S).fonts.map((x) => [x.file, mediaUrl(x.url)]),
  );
  return f.html
    .replace(/<script\b[\s\S]*?<\/script>/gi, "")
    .replace(
      /url\("fonts\/([^"]+)"\)/g,
      (m, file) => `url("${urls[file] || ""}")`,
    )
    .replace(
      "</head>",
      () => `<style id="edits">${paletteCss(S)}</style></head>`,
    );
}

function view(S) {
  const c = latest(S);
  if (S.mode === "nodb")
    return shell(
      S,
      "This page cannot reach its database here, so no card can load. Say so in the terminal, and the session carries on there.",
    );
  if (!c)
    return shell(
      S,
      S.mode === "loading"
        ? "Loading the style card."
        : "Waiting for card 1. Claude posts it here in a moment.",
    );
  return `<div class="wrap">
    <header class="hdr"><span class="label">explainer-video · style card ${esc(c.version)}</span><h1>${esc(c.label)}</h1>
      <p class="lede">The draft profile on sample frames that play live as they come into view, the last across a seam. Edit a colour or a font right here, then save the profile, use it once for this video, or ask for a revision.</p>
      ${c.source ? `<p class="label">${esc(c.source)}</p>` : ""}
      ${S.canEdit ? "" : '<p class="label">Only an editor of this page answers its cards.</p>'}</header>
    ${c.findings.length ? `<div class="banner panel" role="alert"><b>These frames break the video gates' layout rules, so Save and Use once wait for an edit or a revision.</b><pre>${c.findings.map(esc).join("\n")}</pre></div>` : ""}
    <section class="frames" id="frames">${c.frames
      .map(
        (f) =>
          `<figure class="shot panel"><span class="label">${esc(f.label)}</span><div class="frame" data-stage="${esc(f.id)}"><iframe sandbox="allow-same-origin" title="${esc(f.label)} frame" data-frame="${esc(f.id)}" srcdoc="${esc(frameDoc(S, f))}"></iframe>${S.inView[f.id] ? `<iframe sandbox="allow-scripts" class="live" title="${esc(f.label)} playing" data-live="${esc(f.id)}"></iframe>` : ""}</div></figure>`,
      )
      .join("")}</section>
    ${grammarPanel(c)}
    ${palettePanel(S, c)}
    ${typePanel(S, c)}
    ${decision(S, c)}
  </div>${bar(S, c)}`;
}
function shell(S, text) {
  return `<div class="wrap"><header class="hdr"><span class="label">explainer-video · style card</span><h1>${esc(S.title)}</h1></header><p class="notice panel" role="status">${esc(text)}</p></div>`;
}
function contrastNote(S) {
  const bad = failing(S);
  return `<div data-live="contrast">${
    bad.length
      ? `<ul class="fails" role="alert">${bad.map((x) => `<li>${esc(x)}</li>`).join("")}</ul>`
      : '<p class="ok-line">Every colour passes contrast by role.</p>'
  }</div>`;
}
// Each grammar field with how it was reached; the page edits none of them.
function grammarPanel(c) {
  return `<section class="edit panel"><h2>Grammar</h2><div class="rows">${c.grammar
    .map(
      (g) =>
        `<div class="grow"><span class="label">${esc(g.field)}</span>
      <span>${esc(g.value)}</span><span class="why"><span class="tag${g.mark === "measured" || g.mark === "judged" ? " accent" : ""}">${esc(g.mark)}</span>${g.why ? `<span>${esc(g.why)}</span>` : ""}</span></div>`,
    )
    .join("")}</div></section>`;
}
function palettePanel(S, c) {
  const d = draftOf(S),
    dis = locked(S) ? "disabled" : "";
  return `<section class="edit panel"><h2>Colours</h2><div class="rows">${c.colors
    .map((x) => {
      const v = d.colors[x.token],
        changed = v.toLowerCase() !== x.hex.toLowerCase();
      return `<div class="row"><span class="label">${esc(x.token)}</span>
      <input type="color" id="pick-${esc(x.token)}" data-color="${esc(x.token)}" value="${esc(HEX.test(v) ? v.toLowerCase() : x.hex)}" aria-label="${esc(x.token)} colour" ${dis}>
      <input type="text" id="hex-${esc(x.token)}" data-hex="${esc(x.token)}" value="${esc(v)}" spellcheck="false" aria-label="${esc(x.token)} hex" ${dis}>
      <span class="why" data-live="why-${esc(x.token)}"><span class="tag${changed ? " accent" : ""}">${changed ? "edited" : esc(x.mark)}</span>${x.why ? `<span>${esc(x.why)}</span>` : ""}</span></div>`;
    })
    .join("")}</div>${contrastNote(S)}</section>`;
}
function typePanel(S, c) {
  const d = draftOf(S),
    dis = locked(S) ? "disabled" : "";
  const why = (x) =>
    x.mark
      ? `<span class="why"><span class="tag">${esc(x.mark)}</span><span>${esc(x.why)}</span></span>`
      : "";
  return `<section class="edit panel"><h2>Type</h2><div class="rows">${c.type
    .map((x) =>
      LATIN.includes(x.role)
        ? `<label class="trow"><span class="label">${esc(x.role)}</span><select id="font-${esc(x.role)}" data-font="${esc(x.role)}" ${dis}>${c.families
            .map(
              (f) =>
                `<option value="${esc(f)}" ${d.type[x.role] === f ? "selected" : ""}>${esc(f)}</option>`,
            )
            .join("")}</select>${why(x)}</label>`
        : `<div class="trow"><span class="label">${esc(x.role)}</span><span>${esc(x.font)}</span>${why(x)}</div>`,
    )
    .join("")}</div>
    <p class="label">A font change shows on the next card, once the run has gated it.</p></section>`;
}
function decision(S, c) {
  const d = draftOf(S),
    dis = locked(S) ? "disabled" : "";
  const radio = ([v, label]) =>
    `<label><input type="radio" name="choice" value="${v}" ${d.choice === v ? "checked" : ""} ${dis}>${label}</label>`;
  return `<section class="edit panel"><h2>Your answer</h2>
    <fieldset class="choices"><legend class="label">Save it to the ${esc(c.scope)} store, use it for this video only, or ask for a revision</legend>${CHOICES.map(radio).join("")}</fieldset>
    <label class="field"><span class="label">Name (lowercase words joined by hyphens)</span><input type="text" id="name" data-set="name" value="${esc(d.name)}" spellcheck="false" ${dis}></label>
    <div data-live="options">${taken(S) ? `<label class="check"><input type="checkbox" id="replace" data-set="replace" ${d.replace ? "checked" : ""} ${dis}>Replace the saved ${esc(d.name)}</label>` : ""}
    ${d.choice === "save" ? `<label class="check"><input type="checkbox" id="default" data-set="default" ${d.default ? "checked" : ""} ${dis}>Make it the ${esc(c.scope)} store's default</label>` : ""}</div>
    <label class="field"><span class="label">Note (what to change, optional)</span><textarea rows="2" id="note" data-set="note" ${dis}>${esc(d.note)}</textarea></label></section>`;
}
function bar(S, c) {
  if (!S.canEdit) return "";
  const why = blockers(S);
  const act = S.local
    ? `<button class="btn accent" data-act="copy" ${why.length ? "disabled" : ""}>Copy answers</button>`
    : `<button class="btn accent" id="submit" data-act="submit" ${canSubmit(S) ? "" : "disabled"}>Submit card ${esc(c.version)}</button>`;
  return `<div class="bar panel" data-live="bar"><div class="bar-in">
    <span class="count">${why.length && !S.submitted[c.version] ? esc(why[0]) : "Ready to submit."}</span>
    <div>${act}</div>${S.local ? localNote(S) : status(S)}</div></div>`;
}
function localNote(S) {
  return `<div class="st"><span>Copy the answers, paste them into the terminal, and Claude reads them.</span>
    <pre id="fallback-text">${esc(answersText(S))}</pre><span class="label" id="copied" role="status"></span></div>`;
}
function status(S) {
  const n = latest(S).version;
  switch (S.status) {
    case "sending":
      return '<div class="st" role="status">Saving your answers and waking Claude.</div>';
    case "sent":
      return '<div class="st st-ok" role="status"><span><b>Sent to Claude.</b> An edit or revision brings the next card to this page; Save and Use once carry on in the terminal. If nothing happens, type <code>submitted</code> in the terminal.</span></div>';
    case "saved":
      return `<div class="st st-warn" role="alert"><span><b>Saved, but Claude was not woken.</b> Type <code>submitted</code> in the terminal and the session reads your saved answers.</span>
      <div class="st-row"><button class="btn btn-sm" data-act="wake">Try waking it again</button></div></div>`;
    case "neither":
      return `<div class="st st-bad" role="alert"><span><b>Your answers were not saved.</b> Copy them and paste them into the terminal.</span>
      <pre id="fallback-text">${esc(answersText(S))}</pre>
      <div class="st-row"><button class="btn btn-sm accent" data-act="copy">Copy answers</button><button class="btn btn-sm" data-act="submit">Try again</button><span class="label" id="copied" role="status"></span></div></div>`;
  }
  if (S.submitted[n])
    return `<div class="st st-ok" role="status"><span><b>Submitted.</b> If no new card appears and the terminal shows nothing, type <code>submitted</code> there.</span></div>`;
  return "";
}

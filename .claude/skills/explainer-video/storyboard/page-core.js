/* ---- core: state in, HTML out. No DOM here, so the page can run headless against board-data.md. ---- */
const CARD_TAG = {
  open: ["Open", "accent"],
  approved: ["Approved", "ok"],
  reopened: ["Reopened", "warn"],
};

function newState(title) {
  return {
    title,
    boards: [],
    submitted: {},
    drafts: {},
    status: "idle",
    mode: "loading",
    canEdit: true,
    local: false,
    playing: null,
    // The one card in view, whose build is mounted; the animatic mounts its own.
    inView: {},
    animatic: false,
  };
}
const latest = (S) => S.boards[S.boards.length - 1];
function newDraft(b) {
  const d = {
    choices: {},
    narr: {},
    notes: {},
    picks: {},
    was: {},
    brief: {},
    kept: {},
  };
  for (const c of b.scenes) {
    d.choices[c.id] = c.recommendation;
    d.narr[c.id] = c.narration;
    d.notes[c.id] = "";
    d.picks[c.id] = {};
  }
  for (const k of b.brief) d.brief[k.knob] = k.value;
  for (const t of b.kept || []) d.kept[t] = t;
  return d;
}
function draftOf(S) {
  const b = latest(S);
  if (!S.drafts[b.version]) S.drafts[b.version] = newDraft(b);
  return S.drafts[b.version];
}
function setBoards(S, docs) {
  const was = latest(S) && latest(S).version;
  S.boards = docs.slice().sort((a, b) => a.version - b.version);
  S.mode = "ready";
  if (latest(S) && latest(S).version !== was) {
    S.status = "idle";
    S.playing = null;
    S.animatic = false;
  }
}
// A card loops its slot, which holds the scene's exit seam.
const loopOf = (c) => [c.start, c.start + c.slot];
// The scene playing at narration time t: the last one begun, so a seam belongs to the scene it enters.
const sceneAt = (b, t) =>
  b.scenes.reduce((on, c) => (c.start <= t ? c : on), b.scenes[0]);
const buildOf = (b) => mediaUrl(b.build);
function setAnswers(S, docs) {
  S.submitted = Object.fromEntries(docs.map((d) => [d.version, true]));
}

const locked = (S) => {
  const b = latest(S);
  return (
    !S.canEdit ||
    b.kind === "delivered" ||
    ["sending", "sent", "saved"].includes(S.status) ||
    !!S.submitted[b.version]
  );
};
// A failed save leaves the comment as the only copy, so it counts as sent only when it held the whole answers.
const outcome = (saved, woke, whole) =>
  woke && (saved || whole) ? "sent" : saved ? "saved" : "neither";
const needs = (c) => c.status !== "approved";
const todoN = (S) =>
  latest(S).scenes.filter((c) => needs(c) && !draftOf(S).choices[c.id]).length;
const canSubmit = (S) => !!latest(S) && !locked(S) && todoN(S) === 0;

const ACT = {
  choose(S, d) {
    if (locked(S)) return;
    draftOf(S).choices[d.id] = d.choice;
    delete draftOf(S).was[d.id];
  },
  // A note or an edited narration is a request to change the scene: it answers Revise.
  field(S, d) {
    if (locked(S)) return;
    const dr = draftOf(S);
    dr[d.field === "note" ? "notes" : "narr"][d.id] = d.value;
    const c = latest(S).scenes.find((x) => x.id === d.id);
    if (d.field === "note" ? d.value.trim() : d.value !== c.narration)
      dr.choices[d.id] = "revise";
  },
  // A menu set to another option than the agent's pick is a request to change the scene: it answers Revise.
  // The answer it replaced is kept in `was`, and comes back once nothing on the card asks for a change.
  pick(S, d) {
    if (locked(S)) return;
    const dr = draftOf(S);
    dr.picks[d.id][d.menu] = d.value;
    const c = latest(S).scenes.find((x) => x.id === d.id);
    if (d.value !== c.menus[d.menu].pick) {
      if (dr.choices[d.id] !== "revise") dr.was[d.id] = dr.choices[d.id] || "";
      dr.choices[d.id] = "revise";
    } else if (d.id in dr.was && !asks(S, c)) {
      dr.choices[d.id] = dr.was[d.id];
      delete dr.was[d.id];
    }
  },
  approveAll(S) {
    if (!locked(S))
      for (const c of latest(S).scenes) draftOf(S).choices[c.id] = "approve";
  },
  brief(S, d) {
    if (locked(S)) return;
    const dr = draftOf(S);
    dr.brief[d.knob] = d.value;
    // A voice belongs to a language: another language takes its first voice unless the pick is one of its own.
    const opts = voiceOptions(S);
    if (d.knob === "language" && opts && !opts.includes(dr.brief.voice))
      dr.brief.voice = opts[0];
  },
  kept(S, d) {
    if (!locked(S)) draftOf(S).kept[d.term] = d.value;
  },
};

// The voices of the language the draft brief holds, or undefined when the board lists none.
const voiceOptions = (S) =>
  latest(S).voices.find((v) => v.language === draftOf(S).brief.language)
    ?.options;
// A card's menu picks that differ from the agent's own.
const changedPicks = (S, c) =>
  Object.fromEntries(
    Object.entries(draftOf(S).picks[c.id]).filter(
      ([m, v]) => v !== c.menus[m].pick,
    ),
  );

// Whether the card still asks for a change: a changed pick, a note or an edited narration.
const asks = (S, c) =>
  Object.keys(changedPicks(S, c)).length > 0 ||
  !!draftOf(S).notes[c.id].trim() ||
  draftOf(S).narr[c.id] !== c.narration;

// Each kept term edited to a new non-empty spelling, as `{term, to}`.
function keptEdits(S) {
  const b = latest(S),
    d = draftOf(S);
  return (b.kept || [])
    .filter((t) => d.kept[t].trim() && d.kept[t].trim() !== t)
    .map((t) => ({ term: t, to: d.kept[t].trim() }));
}

// Changed knobs as `knob=value`; a changed list is one `knob=<item>` per item, an emptied one a lone `knob=`.
function briefArgs(S) {
  const b = latest(S),
    d = draftOf(S),
    out = [];
  for (const k of b.brief) {
    const v = d.brief[k.knob];
    if (v === k.value) continue;
    if (k.knob === "must" || k.knob === "avoid") {
      const items = v
        .split(";")
        .map((x) => x.trim())
        .filter(Boolean);
      out.push(...(items.length ? items : [""]).map((x) => k.knob + "=" + x));
    } else out.push(k.knob + "=" + v.trim());
  }
  return out;
}
function answersDoc(S, at = new Date().toISOString()) {
  const b = latest(S),
    d = draftOf(S);
  return {
    version: b.version,
    submittedAt: at,
    scenes: b.scenes.map((c) => ({
      id: c.id,
      choice: d.choices[c.id],
      note: d.notes[c.id].trim(),
      narration:
        d.narr[c.id].trim() && d.narr[c.id] !== c.narration ? d.narr[c.id] : "",
      picks: changedPicks(S, c),
    })),
    brief: briefArgs(S),
    ...(b.kept && { kept: keptEdits(S) }),
  };
}
function answersText(S) {
  const n = latest(S).version;
  // Names the database document without claiming the save worked: this text is also the fallback.
  const lines = [
    `explainer-video: board ${n} answers (database document answers/board-${n})`,
  ];
  const doc = answersDoc(S);
  for (const c of doc.scenes) {
    lines.push(
      `${c.id}: ${c.choice === "approve" ? "Approve" : c.choice === "revise" ? "Revise" : "Unanswered"}`,
    );
    if (c.note) lines.push("  note: " + c.note.replace(/\s*\n\s*/g, " "));
    if (c.narration)
      lines.push(
        "  narration:",
        ...c.narration.split("\n").map((l) => "    " + l),
      );
    for (const [m, v] of Object.entries(c.picks))
      lines.push(`  pick: ${m}=${v}`);
  }
  for (const a of doc.brief) lines.push("Brief: " + a);
  for (const k of doc.kept || []) lines.push("Kept: " + k.term + " -> " + k.to);
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
  if (/^https:/i.test(s) || s.startsWith("/_blob/")) return s;
  return /^[a-z][a-z0-9+.-]*:/i.test(s) || s.startsWith("/") ? "" : s;
}

function view(S) {
  const b = latest(S);
  if (S.mode === "nodb")
    return shell(
      S,
      "This page cannot reach its database here, so no board can load. Say so in the terminal, and the session carries on there.",
    );
  if (!b)
    return shell(
      S,
      S.mode === "loading"
        ? "Loading the storyboard."
        : "Waiting for board 1. Claude posts it here in a moment.",
    );
  const delivered = b.kind === "delivered";
  const lede = delivered
    ? "The video is made. Each card plays its own stretch of it; nothing is left to answer."
    : "Check each scene: approve it or revise it, edit its narration right on the card, and change the brief if the whole video should differ. Then submit.";
  return `<div class="wrap">
    <header class="hdr"><span class="label">explainer-video · board ${esc(b.version)}</span><h1 dir="auto">${esc(b.title)}</h1><p class="lede">${lede}</p>
      ${S.canEdit || delivered ? "" : '<p class="label">Only an editor of this page answers its boards.</p>'}</header>
    ${b.banner ? banner(b.banner) : ""}
    ${delivered ? "" : overview(b)}
    ${player(S, b)}
    ${delivered ? "" : estimatePanel(b)}
    ${briefPanel(S, b)}
    ${sourcesPanel(b)}
    <section class="cards">${cardList(S, b)}</section>
  </div>${delivered ? "" : bar(S, b)}`;
}
function shell(S, text) {
  return `<div class="wrap"><header class="hdr"><span class="label">explainer-video · board</span><h1 dir="auto">${esc(S.title)}</h1></header><p class="notice panel" role="status">${esc(text)}</p></div>`;
}
function banner(x) {
  return `<div class="banner panel" role="alert"><b>${esc(x.text)}</b><pre>${x.gates.map(esc).join("\n")}</pre></div>`;
}
// A stage is the poster, with the live build over it once a frame is mounted.
const stage = (id, still, frame) =>
  `<div class="stage" data-stage="${esc(id)}"><img alt="" src="${esc(mediaUrl(still))}">${frame}</div>`;
const frame = (id, label) =>
  `<iframe class="live" sandbox="allow-scripts" title="${esc(label)}" data-live="${esc(id)}"></iframe>`;
function player(S, b) {
  const on = b.scenes.find((c) => c.id === S.playing) || b.scenes[0];
  return `<section class="player panel" id="player"><span class="label">Animatic</span>
    ${stage("animatic", on.still, S.animatic ? frame("animatic", "Live build of the whole video") : "")}
    <audio id="player-audio" preload="none" src="${esc(mediaUrl(b.narration))}"></audio>
    <div class="row"><button class="btn btn-sm accent" data-act="play">Play animatic</button><button class="btn btn-sm" data-act="stop">Stop</button>
      <span class="label">Plays the whole build over the joined narration, seams included.</span></div>
    <ol class="scenes">${b.scenes
      .map(
        (c) =>
          `<li><button class="scene${S.playing === c.id ? " on" : ""}" data-act="jump" data-id="${esc(c.id)}" ${S.playing === c.id ? 'aria-current="true"' : ""}><span dir="auto">${esc(c.title)}</span><span class="label">${esc(c.seconds)} s</span></button></li>`,
      )
      .join("")}</ol></section>`;
}
// A select over `options`, the one equal to `cur` picked; `attrs` is its data attributes.
const select = (attrs, options, cur, off) =>
  `<select ${attrs} ${off ? "disabled" : ""}>${options
    .map(
      (o) =>
        `<option value="${esc(o)}"${o === cur ? " selected" : ""}>${esc(o)}</option>`,
    )
    .join("")}</select>`;
// One knob's input: a select for a menu knob (its voices those of the language picked), a number of minutes, or text.
function knobInput(S, k, dis) {
  const v = draftOf(S).brief[k.knob],
    at = `data-brief="${esc(k.knob)}"`;
  if (k.type === "menu")
    return select(
      at,
      (k.knob === "voice" && voiceOptions(S)) || k.options,
      v,
      dis,
    );
  const kind = k.type === "number" ? 'number" min="1" step="any' : "text";
  return `<input type="${kind}" ${at} value="${esc(v)}" ${dis}>`;
}
function briefPanel(S, b) {
  const d = draftOf(S),
    dis = locked(S) ? "disabled" : "";
  const kept = b.kept || [];
  if (!b.brief.length && !kept.length) return "";
  // Kept terms stay English in speech, on screen and in captions; a new spelling here changes all three.
  return `<section class="brief panel"><span class="label">Brief</span><div class="knobs">${b.brief
    .map(
      (k) =>
        `<label class="knob"><span class="label">${esc(k.knob)}</span>${knobInput(S, k, dis)}</label>`,
    )
    .join("")}</div>${
    kept.length
      ? `<span class="label">Kept terms</span><div class="knobs">${kept
          .map(
            (t) =>
              `<label class="knob"><span class="label">${esc(t)}</span><input type="text" dir="auto" data-kept="${esc(t)}" value="${esc(d.kept[t])}" ${dis}></label>`,
          )
          .join("")}</div>`
      : ""
  }</section>`;
}
function sourcesPanel(b) {
  if (!b.sources.length) return "";
  return `<section class="sources panel"><span class="label">Sources</span>${b.sources
    .map(
      (s) =>
        `<div class="src"><span><b>${esc(s.id)}</b> · ${esc(s.kind)} · ${esc(s.title)}</span><span>${esc(s.summary)}</span><span class="label">${esc(s.excerpts)} excerpt${s.excerpts === 1 ? "" : "s"}</span></div>`,
    )
    .join("")}</section>`;
}
function card(S, b, c) {
  const d = draftOf(S),
    dis = locked(S) ? "disabled" : "",
    delivered = b.kind === "delivered";
  const [tagText, tagClass] = CARD_TAG[c.status] || CARD_TAG.open;
  const radio = (v, label) =>
    `<label><input type="radio" name="c-${esc(c.id)}" value="${v}" data-id="${esc(c.id)}" ${d.choices[c.id] === v ? "checked" : ""} ${dis}>${label}${c.recommendation === v ? ' <span class="label">recommended</span>' : ""}</label>`;
  const media =
    delivered && c.clip
      ? `<video controls preload="none" src="${esc(mediaUrl(c.clip))}" poster="${esc(mediaUrl(c.still))}"></video>`
      : stage(
          c.id,
          c.still,
          S.inView[c.id] && !S.animatic
            ? frame(c.id, "Live build of scene " + c.id)
            : "",
        );
  const body = `<div class="chead"><h3 dir="auto">${esc(c.title)}</h3>${c.role ? `<span class="tag">${esc(c.role)}</span>` : ""}<span class="tag">${esc(c.seconds)} s</span><span class="tag ${tagClass}" data-tag="${esc(c.id)}">${tagText}</span></div>
    ${media}
    <span class="style">${esc(c.style)}</span>
    ${c.adds === undefined ? "" : `<span class="label" data-adds>adds <b>+${esc(c.adds)} s</b> to the render</span>`}
    ${c.intent ? `<p class="intent" dir="auto"><span class="label">Intent</span> ${esc(c.intent)}</p>` : ""}
    ${
      c.finding
        ? `<div class="finding" role="note"><span class="label">Finding</span><pre>${esc(c.finding)}</pre>${c.fix ? `<p dir="auto"><span class="label">Proposed fix</span> ${esc(c.fix)}</p>` : ""}</div>`
        : ""
    }
    ${
      delivered && c.clip
        ? `<audio controls preload="none" src="${esc(mediaUrl(c.audio))}"></audio>`
        : `<div class="row"><button class="btn btn-sm accent" data-act="card-play" data-id="${esc(c.id)}">Play</button>
      <audio preload="none" data-audio="${esc(c.id)}" src="${esc(mediaUrl(c.audio))}"></audio></div>`
    }
    ${
      delivered
        ? `<p dir="auto">${esc(c.narration).replace(/\n/g, "<br>")}</p>`
        : `<label class="field"><span class="label">Narration (edit to reword)</span>
      <textarea dir="auto" rows="4" data-field="narration" data-id="${esc(c.id)}" ${dis}>${esc(d.narr[c.id])}</textarea></label>
    <div class="menus">${Object.entries(c.menus)
      .map(
        ([m, x]) =>
          `<label class="knob"><span class="label">${m}</span>${select(`data-menu="${m}" data-id="${esc(c.id)}"`, x.options, d.picks[c.id][m] ?? x.pick, dis || x.disabled)}</label>`,
      )
      .join("")}</div>
    <fieldset class="choices"><legend class="label">Your answer</legend>${radio("approve", "Approve")}${radio("revise", "Revise")}</fieldset>
    <label class="field"><span class="label">Note (what to change, optional)</span>
      <textarea dir="auto" rows="2" data-field="note" data-id="${esc(c.id)}" ${dis}>${esc(d.notes[c.id])}</textarea></label>`
    }`;
  const cls = `card panel${S.playing === c.id ? " playing" : ""}`;
  return c.status === "approved" && !delivered
    ? `<details class="${cls}" id="card-${esc(c.id)}" data-card="${esc(c.id)}" data-state="approved"><summary>${esc(c.id)} · ${esc(c.title)} <span class="tag ok">Approved</span></summary>${body}</details>`
    : `<article class="${cls}" id="card-${esc(c.id)}" data-card="${esc(c.id)}" data-state="${esc(c.status)}">${body}</article>`;
}
function bar(S, b) {
  if (!S.canEdit) return "";
  const need = b.scenes.filter(needs).length,
    left = todoN(S);
  const act = S.local
    ? `<button class="btn accent" data-act="copy" ${left ? "disabled" : ""}>Copy answers</button>`
    : `<button class="btn accent" id="submit" data-act="submit" ${canSubmit(S) ? "" : "disabled"}>Submit board ${esc(b.version)}</button>`;
  return `<div class="bar panel"><div class="bar-in">
    <span class="count"><b data-ready>${need - left}</b> of ${need} to answer done · ${b.scenes.length - need} already approved</span>
    <div><button class="btn" data-act="approve-all" ${locked(S) ? "disabled" : ""}>${S.local ? "Approve all" : "Approve all and submit"}</button> ${act}</div>${S.local ? localNote(S) : status(S)}</div></div>`;
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
      return '<div class="st st-ok" role="status"><span><b>Sent to Claude.</b> The next board appears on this page; if it does not, type <code>submitted</code> in the terminal.</span></div>';
    case "saved":
      return `<div class="st st-warn" role="alert"><span><b>Saved, but Claude was not woken.</b> Type <code>submitted</code> in the terminal and the session reads your saved answers.</span>
      <div class="st-row"><button class="btn btn-sm" data-act="wake">Try waking it again</button></div></div>`;
    case "neither":
      return `<div class="st st-bad" role="alert"><span><b>Your answers were not saved.</b> Copy them and paste them into the terminal.</span>
      <pre id="fallback-text">${esc(answersText(S))}</pre>
      <div class="st-row"><button class="btn btn-sm accent" data-act="copy">Copy answers</button><button class="btn btn-sm" data-act="submit">Try again</button><span class="label" id="copied" role="status"></span></div></div>`;
  }
  if (S.submitted[n])
    return `<div class="st st-ok" role="status"><span><b>Submitted.</b> Waiting for board ${esc(n + 1)}. If it does not appear, type <code>submitted</code> in the terminal.</span></div>`;
  return "";
}

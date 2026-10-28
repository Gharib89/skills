/* creative-video's storyboard page: the board document of board-data.md in, the answers document out.
   The top half is pure (state in, HTML out, no DOM), so a test runs it headless through `Board`; the
   bottom half boots only where a document exists. Forked from explainer-video's page and cut down: no
   menus, no animatic, no live build and no narration editing, and one approval for the whole look. */
const MAX_COMMENT = 4096;

function newState(board) {
  return {
    board,
    tab: 1,
    // The answers documents the database holds; empty on a local page.
    answers: [],
    // What the person has changed: another direction, a comment on the look, a note per scene.
    draft: { direction: null, look: "", notes: {} },
    // What Submit was asked for: "approve" or "send". An approval holds only while nothing is commented.
    intent: null,
    // idle, sending, sent, saved (written, Claude not woken) or neither.
    status: "idle",
    mode: "ready",
    local: false,
  };
}

const noteOf = (S, id) => (S.draft.notes[id] || "").trim();
const hasComments = (S) =>
  !!S.draft.direction ||
  !!S.draft.look.trim() ||
  S.board.scenes.some((c) => noteOf(S, c.id));
const canApprove = (S) => !!S.board && !hasComments(S);
const canSend = (S) => !!S.board && hasComments(S);
// A database page takes one answer per board version; a local page copies as often as it likes.
const answered = (S) => S.answers.some((a) => a.version === S.board.version);
const locked = (S) =>
  !S.local && (["sending", "sent", "saved"].includes(S.status) || answered(S));
function setAnswers(S, docs) {
  S.answers = docs;
}
// A chapter is approved once an approving answers document of the latest version is in the database.
function statusOf(S, n) {
  if (
    S.answers.some((a) => a.version === S.board.version && a.approve === true)
  )
    return "approved";
  const c = S.board.chapters.find((x) => x.n === n);
  return c.status === "awaiting" ? "awaiting you" : c.status;
}

const ACT = {
  note(S, d) {
    if (!locked(S)) S.draft.notes[d.id] = d.value;
  },
  look(S, d) {
    if (!locked(S)) S.draft.look = d.value;
  },
  // Another direction is a pick; picking it again takes it back. The one in use takes no pick.
  direction(S, d) {
    if (locked(S) || S.board.directions.find((x) => x.id === d.id).picked)
      return;
    S.draft.direction = S.draft.direction === d.id ? null : d.id;
  },
  approve(S) {
    if (!locked(S) && canApprove(S)) S.intent = "approve";
  },
  send(S) {
    if (!locked(S) && canSend(S)) S.intent = "send";
  },
  tab(S, d) {
    S.tab = d.n;
  },
};

function answersDoc(S, at = new Date().toISOString()) {
  return {
    version: S.board.version,
    submittedAt: at,
    approve: S.intent === "approve" && canApprove(S),
    direction: S.draft.direction,
    look: S.draft.look.trim(),
    scenes: S.board.scenes
      .filter((c) => noteOf(S, c.id))
      .map((c) => ({ id: c.id, note: noteOf(S, c.id) })),
  };
}
// The text apply reads: the page's copy button and the Submit comment carry it. A text continues on lines
// indented two spaces. It names the database document without claiming the save worked, for it is also
// the fallback.
function answersText(doc) {
  const more = (t) => t.replaceAll("\n", "\n  ");
  const lines = [
    `creative-video: board ${doc.version} answers (database document answers/board-${doc.version})`,
  ];
  if (doc.approve) lines.push("Approved: the look");
  if (doc.direction) lines.push(`Direction: ${doc.direction}`);
  if (doc.look) lines.push(`Look: ${more(doc.look)}`);
  for (const c of doc.scenes) lines.push(`${c.id}: ${more(c.note)}`);
  return lines.join("\n");
}
// The comment is the doorbell, so it holds the 4 KiB a comment can; the document is in the database.
function capped(text, n) {
  const enc = new TextEncoder(),
    tail = `\n[cut to fit: read answers/board-${n}]`;
  if (enc.encode(text).length <= MAX_COMMENT) return text;
  let s = text;
  while (enc.encode(s + tail).length > MAX_COMMENT) s = s.slice(0, -64);
  return s + tail;
}
// A failed save leaves the comment as the only copy, so it counts as sent only when it held the whole answers.
const outcome = (saved, woke, whole) =>
  woke && (saved || whole) ? "sent" : saved ? "saved" : "neither";

const esc = (s) =>
  String(s == null ? "" : s).replace(
    /[&<>"]/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c],
  );
// A still is https, the artifact's own /_blob/, or a path relative to the page; nothing else reaches src.
function mediaUrl(u) {
  const s = String(u == null ? "" : u);
  if (/^https:/i.test(s) || s.startsWith("/_blob/")) return s;
  return /^[a-z][a-z0-9+.-]*:/i.test(s) || s.startsWith("/") ? "" : s;
}

function view(S) {
  const b = S.board;
  if (!b)
    return `<div class="wrap"><p class="notice panel" role="status">This page holds no board. Say so in the terminal, and the session builds it again.</p></div>`;
  const chapter = b.chapters.find((c) => c.n === S.tab) || b.chapters[0];
  return `<div class="wrap">
    <header class="hdr"><span class="label">creative-video · board ${esc(b.version)}</span><h1 dir="auto">${esc(b.title)}</h1>
      <p class="lede">${esc(b.length)} · ${esc(b.language)}. Look at each scene's three stills. Comment on a scene to have only that scene made again, comment on the whole look, or pick another direction. Approving covers the whole video.</p></header>
    <nav class="tabs" role="tablist">${b.chapters.map((c) => tab(S, c)).join("")}</nav>
    <section class="chapter" role="tabpanel" aria-labelledby="tab-${esc(chapter.n)}">
      ${chapter.n === 1 ? directionsPanel(S, b) : ""}
      <div class="cards">${b.scenes
        .filter((c) => c.chapter === chapter.n)
        .map((c) => card(S, c))
        .join("")}</div>
    </section>
    ${lookPanel(S)}
    ${planPanel(S, b)}
  </div>${S.mode === "ready" ? bar(S, b) : ""}`;
}
const statusTag = (S, n) =>
  `<span class="tag ${statusOf(S, n) === "approved" ? "ok" : "accent"}" data-status="${esc(n)}">${statusOf(S, n)}</span>`;
function tab(S, c) {
  const on = c.n === S.tab;
  return `<button class="tab" role="tab" id="tab-${esc(c.n)}" aria-selected="${on}" data-act="tab" data-n="${esc(c.n)}">${esc(c.n)} · ${esc(c.title)} ${statusTag(S, c.n)}</button>`;
}
function directionsPanel(S, b) {
  const dis = locked(S) ? "disabled" : "";
  return `<section class="dirs panel"><h2>Direction for the video</h2>
    <p class="lede">One idea owns the whole film. The one in use is what the scenes below are made in; use another and the chapter is made again in it.</p>
    <div class="dirgrid">${b.directions
      .map((d) => {
        const mine = S.draft.direction === d.id;
        return `<figure class="dir${d.picked ? " in-use" : ""}${mine ? " chosen" : ""}" data-direction="${esc(d.id)}">
        <img alt="${esc(d.name)}" src="${esc(mediaUrl(d.frame))}">
        <figcaption><b dir="auto">${esc(d.name)}</b> <span class="label">${esc(d.kind)}</span>
          ${d.recommended ? '<span class="tag accent">Recommended</span>' : ""}${d.picked ? '<span class="tag ok">In use</span>' : ""}${mine ? '<span class="tag warn">Your pick</span>' : ""}
          ${d.picked ? "" : `<button class="btn btn-sm" data-act="direction" data-id="${esc(d.id)}" ${dis}>${mine ? "Take back" : "Use this direction"}</button>`}</figcaption></figure>`;
      })
      .join("")}</div></section>`;
}
function card(S, c) {
  const dis = locked(S) ? "disabled" : "";
  const still = (phase) =>
    `<figure><img alt="${esc(c.title)}, ${phase}" src="${esc(mediaUrl(c.stills[phase]))}"><figcaption class="label">${phase}</figcaption></figure>`;
  return `<article class="card panel" id="scene-${esc(c.id)}" data-card="${esc(c.id)}">
    <div class="chead"><h3 dir="auto">${esc(c.title)}</h3><span class="tag">${esc(c.timecode)}</span>${c.changed ? '<span class="tag accent">changed</span>' : ""}</div>
    <div class="stills">${["in", "key", "out"].map(still).join("")}</div>
    <p dir="auto"><span class="label">Narration</span> ${esc(c.narration)}</p>
    <p dir="auto"><span class="label">Notes</span> ${esc(c.notes)}</p>
    <label class="field"><span class="label">Comment on this scene</span>
      <textarea dir="auto" rows="2" id="note-${esc(c.id)}" data-field="note" data-id="${esc(c.id)}" ${dis}>${esc(S.draft.notes[c.id] || "")}</textarea></label></article>`;
}
function lookPanel(S) {
  return `<section class="look panel"><label class="field"><span class="label">Colours, theme, the whole look</span>
    <textarea dir="auto" rows="3" id="look" data-field="look" ${locked(S) ? "disabled" : ""}>${esc(S.draft.look)}</textarea></label></section>`;
}
function planPanel(S, b) {
  return `<section class="plan panel"><span class="label">Chapter plan</span><div class="scroll"><table>
    <thead><tr><th>Chapter</th><th>Title</th><th>Length</th><th>Focus</th><th>Sources</th><th>Status</th></tr></thead>
    <tbody>${b.plan
      .map(
        (p) =>
          `<tr><td>${esc(p.chapter)}</td><td dir="auto">${esc(p.title)}</td><td>${esc(p.length)}</td><td dir="auto">${esc(p.focus)}</td><td dir="auto">${p.sources.length ? esc(p.sources.join(", ")) : "none"}</td><td>${statusTag(S, p.chapter)}</td></tr>`,
      )
      .join("")}</tbody></table></div></section>`;
}
function bar(S, b) {
  const dis = (ok) => (ok && !locked(S) ? "" : "disabled");
  return `<div class="bar panel"><div class="bar-in">
    <span class="count">${hasComments(S) ? "You have comments: send them." : "Nothing commented: the look can be approved."}</span>
    <div><button class="btn accent" id="approve" data-act="approve" ${dis(canApprove(S))}>Approve the look</button> <button class="btn" id="send" data-act="send" ${dis(canSend(S))}>Send comments</button></div>
    ${S.local ? localNote(S) : status(S, b)}</div></div>`;
}
function localNote(S) {
  if (!S.intent)
    return '<div class="st"><span>Approve or send, and the answers appear here to paste into the terminal.</span></div>';
  return `<div class="st"><span>Paste this into the terminal.</span>
    <pre id="fallback-text">${esc(answersText(answersDoc(S)))}</pre>
    <div class="st-row"><button class="btn btn-sm accent" data-act="copy">Copy</button><span class="label" id="copied" role="status"></span></div></div>`;
}
function status(S, b) {
  switch (S.status) {
    case "sending":
      return '<div class="st" role="status">Saving your answers and waking Claude.</div>';
    case "sent":
      return '<div class="st st-ok" role="status"><span><b>Sent to Claude.</b> The board comes back as a new version of this page; if nothing happens, type <code>submitted</code> in the terminal.</span></div>';
    case "saved":
      return `<div class="st st-warn" role="alert"><span><b>Saved, but Claude was not woken:</b> type <code>submitted</code> in the terminal and the session reads your saved answers.</span>
      <div class="st-row"><button class="btn btn-sm" data-act="wake">Try waking it again</button></div></div>`;
    case "neither":
      return `<div class="st st-bad" role="alert"><span><b>Not saved.</b> Copy the answers and paste them into the terminal.</span>
      <pre id="fallback-text">${esc(answersText(answersDoc(S)))}</pre>
      <div class="st-row"><button class="btn btn-sm accent" data-act="copy">Copy</button><span class="label" id="copied" role="status"></span></div></div>`;
  }
  if (answered(S))
    return `<div class="st st-ok" role="status"><span><b>Answered.</b> Board ${esc(b.version)} has its answers; if the session does not go on, type <code>submitted</code> in the terminal.</span></div>`;
  return "";
}

globalThis.Board = {
  newState,
  ACT,
  canApprove,
  canSend,
  answersDoc,
  answersText,
  capped,
  outcome,
  statusOf,
  setAnswers,
  view,
};

/* ---- boot: the browser only. Wires the capability, the draft, Submit and the copy button. ---- */
if (typeof document !== "undefined") boot();

async function boot() {
  const embedded = () => {
    try {
      return JSON.parse(document.getElementById("board").textContent);
    } catch (e) {
      return null;
    }
  };
  const S = newState(embedded());
  S.mode = "loading";
  const app = document.getElementById("app");
  const key = () => "board-draft-" + S.board.version;
  const saveDraft = () => {
    try {
      localStorage.setItem(key(), JSON.stringify(S.draft));
    } catch (e) {}
  };
  // Only what this board can take: a draft of another board's ids is dropped.
  function restoreDraft() {
    let saved = null;
    try {
      saved = JSON.parse(localStorage.getItem(key()) || "null");
    } catch (e) {}
    if (!saved || typeof saved !== "object") return;
    const picks = S.board.directions.filter((d) => !d.picked).map((d) => d.id);
    if (picks.includes(saved.direction)) S.draft.direction = saved.direction;
    if (typeof saved.look === "string") S.draft.look = saved.look;
    for (const [id, v] of Object.entries(saved.notes || {}))
      if (S.board.scenes.some((c) => c.id === id) && typeof v === "string")
        S.draft.notes[id] = v;
  }
  function render() {
    const f = document.activeElement,
      fid = f && (f.id || null);
    const t = document.createElement("template");
    t.innerHTML = view(S);
    app.replaceChildren(t.content);
    const el = fid && document.getElementById(fid);
    if (el) el.focus({ preventScroll: true });
  }
  // Typing keeps its textarea: only what depends on the draft is updated in place.
  function refresh() {
    for (const [id, ok] of [
      ["approve", canApprove(S)],
      ["send", canSend(S)],
    ]) {
      const b = document.getElementById(id);
      if (b) b.disabled = !ok || locked(S);
    }
    const ft = document.getElementById("fallback-text");
    if (ft) ft.textContent = answersText(answersDoc(S));
  }

  // Listeners first: a local page returns before the capability below.
  document.addEventListener("click", (e) => {
    const t = e.target.closest("[data-act]");
    if (!t || t.disabled || !S.board) return;
    const act = t.dataset.act;
    if (act === "tab") ACT.tab(S, { n: Number(t.dataset.n) });
    else if (act === "direction") ACT.direction(S, { id: t.dataset.id });
    else if (act === "copy") return copy();
    else if (act === "wake") return rewake();
    else if (act === "approve" || act === "send") {
      ACT[act](S);
      if (S.intent !== (act === "approve" ? "approve" : "send")) return;
      if (S.local) return render();
      saveDraft();
      return submit(act);
    } else return;
    saveDraft();
    render();
  });
  document.addEventListener("input", (e) => {
    const t = e.target;
    if (t.dataset.field === "note")
      ACT.note(S, { id: t.dataset.id, value: t.value });
    else if (t.dataset.field === "look") ACT.look(S, { value: t.value });
    else return;
    saveDraft();
    refresh();
  });

  // Every window.claude call goes through here: a page opened as a file has none, which is local mode.
  const use = (name) => {
    try {
      return window.claude && window.claude.use
        ? window.claude.use(name).catch(() => null)
        : Promise.resolve(null);
    } catch (e) {
      return Promise.resolve(null);
    }
  };
  if (!S.board) {
    S.mode = "ready";
    return render();
  }
  restoreDraft();
  render();
  // Declared before the await, not as a const destructure: the listeners above read them.
  let db = null,
    comments = null;
  db = await use("db");
  S.mode = "ready";
  if (!db) {
    S.local = true;
    return render();
  }
  comments = await use("comments");
  db.collection("answers").onSnapshot(
    (snap) => {
      setAnswers(
        S,
        snap.docs.map((d) => d.data()),
      );
      render();
    },
    () => {},
  );
  render();

  // The comment is the doorbell: the one page action that starts a turn in the watching session.
  async function wake(anchor) {
    if (!comments || !anchor) return false;
    try {
      // `available` means this viewer may send, not that a session is watching: a send with no watch
      // lands and wakes nothing, so the sent receipt still names the typed fallback.
      if ((await comments.canSendToClaude()) !== "available") return false;
      await comments.sendToClaude({
        anchor,
        text: capped(answersText(answersDoc(S)), S.board.version),
      });
      return true;
    } catch (e) {
      return false;
    }
  }
  const anchorOf = (id) =>
    comments && document.getElementById(id)
      ? comments.anchorFor(document.getElementById(id)).catch(() => null)
      : Promise.resolve(null);
  async function submit(id) {
    // Lock before any await, so a second click finds the board locked.
    const doc = answersDoc(S);
    S.status = "sending";
    render();
    const anchor = await anchorOf(id);
    const saved = await db
      .doc("answers/board-" + doc.version)
      .set(doc)
      .then(
        () => true,
        () => false,
      );
    const woke = await wake(anchor),
      text = answersText(doc);
    S.status = outcome(saved, woke, capped(text, doc.version) === text);
    render();
  }
  async function rewake() {
    if (S.status !== "saved") return;
    S.status = "sending";
    render();
    const anchor = await anchorOf("send");
    S.status = (await wake(anchor)) ? "sent" : "saved";
    render();
  }
  function copy() {
    const note = (t) => {
      const c = document.getElementById("copied");
      if (c) c.textContent = t;
    };
    const selectIt = () => {
      const r = document.createRange();
      r.selectNodeContents(document.getElementById("fallback-text"));
      const s = getSelection();
      s.removeAllRanges();
      s.addRange(r);
      note("Selected: press Ctrl+C or Cmd+C");
    };
    try {
      navigator.clipboard
        .writeText(answersText(answersDoc(S)))
        .then(() => note("Copied"), selectIt);
    } catch (e) {
      selectIt();
    }
  }
}

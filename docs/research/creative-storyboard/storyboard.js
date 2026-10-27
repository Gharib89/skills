/* global VIDEO, DIRS, DIR_ORDER, SCENES */
// ---------- frames: one parametric SVG per direction ----------
const NODES = {
  switch: ["CALLER", "LEDGER", "OPERATOR", "ROOT", ".COM", "EXAMPLE"],
  direct: ["stub", "cache", "resolver", ".", "com.", "example.com."],
  quiz: ["YOU", "MEMORY", "RESOLVER", "ROOT", ".COM", "EXAMPLE"],
};
const esc = (s) =>
  String(s).replace(
    /[&<>"]/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c],
  );
const X = (i) => 32 + i * 51;

function frame(dir, sc, phase) {
  // phase: "key" (default), "in" or "out", for the three-frame strip
  const f = phase === "in" ? -1 : sc.focus,
    txt = phase === "in" ? "" : sc.screen;
  let g = "";
  if (dir === "switch") {
    g += `<rect width="320" height="180" fill="#2a1d15"/><rect x="10" y="62" width="300" height="106" rx="4" fill="#3a291d" stroke="#d1a94c" stroke-width=".6"/>`;
    NODES.switch.forEach((n, i) => {
      g += `<circle cx="${X(i)}" cy="100" r="9" fill="#d1a94c"/><circle cx="${X(i)}" cy="100" r="4" fill="#1a120c"/>`;
      g += `<rect x="${X(i) - 22}" y="120" width="44" height="13" rx="2" fill="#efe6d2"/><text x="${X(i)}" y="129.5" font-family="Limelight" font-size="6.4" text-anchor="middle" fill="#2a1d15">${n}</text>`;
    });
    if (f >= 0) {
      g += `<circle cx="${X(f)}" cy="100" r="14" fill="none" stroke="#f0cf73" stroke-width="1.5"/>`;
      if (f > 0)
        g += `<path d="M${X(0)},104 C${X(0)},160 ${X(f)},160 ${X(f)},104" fill="none" stroke="#c0392b" stroke-width="3" stroke-linecap="round"/>`;
    }
    if (phase === "out")
      g += `<rect width="320" height="180" fill="#2a1d15" opacity=".45"/>`;
    g += `<text x="160" y="38" font-family="Limelight" font-size="17" text-anchor="middle" fill="#efe6d2">${esc(txt)}</text>`;
  } else if (dir === "direct") {
    const tier = ["#111", "#111", "#111", "#6b4fbb", "#e07a1f", "#2e8b57"];
    g += `<rect width="320" height="180" fill="#fbfbf8"/>`;
    NODES.direct.forEach((n, i) => {
      const on = i === f;
      if (i > 0 && i <= f)
        g += `<line x1="${X(i - 1) + 21}" y1="92" x2="${X(i) - 21}" y2="92" stroke="#111" stroke-width="1.2"/>`;
      g += `<rect x="${X(i) - 21}" y="81" width="42" height="22" rx="3" fill="${on ? tier[i] : "#fff"}" stroke="${tier[i]}" stroke-width="1.2"/>`;
      g += `<text x="${X(i)}" y="95" font-family="IBM Plex Mono" font-size="6.6" text-anchor="middle" fill="${on ? "#fff" : "#111"}">${n}</text>`;
    });
    g += `<text x="16" y="34" font-family="IBM Plex Mono" font-size="12" fill="#111">${esc(txt)}</text>`;
    g += `<rect x="0" y="146" width="320" height="34" fill="#111"/><text x="12" y="167" font-family="IBM Plex Mono" font-size="8" fill="#e8e8e8">$ dig +trace shop.example.com${f >= 3 ? "  ;; referral from " + NODES.direct[f] : ""}</text>`;
    if (phase === "out")
      g += `<rect width="320" height="180" fill="#fbfbf8" opacity=".55"/>`;
  } else {
    g += `<rect width="320" height="180" fill="#ffd23f"/>`;
    NODES.quiz.forEach((n, i) => {
      const on = i === f,
        h = on ? 58 : 44;
      g += `<rect x="${X(i) - 19}" y="${164 - h}" width="38" height="${h}" fill="#14213d"/>`;
      if (on)
        g += `<circle cx="${X(i)}" cy="${164 - h - 8}" r="6" fill="#ee4266"/>`;
      g += `<text x="${X(i)}" y="${164 - h + 14}" font-family="Bungee" font-size="5.6" text-anchor="middle" fill="#fff">${n}</text>`;
    });
    if (txt)
      g += `<rect x="40" y="16" width="240" height="34" rx="6" fill="#ee4266"/><text x="160" y="38" font-family="Bungee" font-size="11" text-anchor="middle" fill="#fff">${esc(txt.toUpperCase())}</text>`;
    g += `<text x="306" y="12" font-family="Bungee" font-size="6" text-anchor="end" fill="#14213d">GUESSES 2/3</text>`;
    if (phase === "out")
      g += `<rect width="320" height="180" fill="#ffd23f" opacity=".5"/>`;
  }
  return `<div class="frame"><svg viewBox="0 0 320 180" role="img" aria-label="${esc(sc.title)}">${g}</svg></div>`;
}

// ---------- shared state (in memory only) ----------
const st = {
  variant: "a",
  dir: "switch",
  pickedB: false,
  comments: [],
  approved: {},
  ch2ready: false,
  cTab: 1,
};
const resetFor = (v) =>
  Object.assign(st, {
    variant: v,
    dir: "switch",
    pickedB: false,
    comments: [],
    approved: {},
    ch2ready: false,
    cTab: 1,
  });

const kitBlock = (d) => {
  const D = DIRS[d];
  return `
  <div class="grid3">
    <div><div class="eyebrow">Palette</div><div class="chips">${D.palette.map(([n, c]) => `<span class="chip"><span class="sw" style="background:${c}"></span>${n}</span>`).join("")}</div></div>
    <div><div class="eyebrow">Type</div><p>${D.type}</p></div>
    <div><div class="eyebrow">Cast and voices</div><p>${D.voices}</p></div>
    <div><div class="eyebrow">Sound cues</div><p>${D.cues}</p></div>
  </div>`;
};

const planTable = (status) => `<div class="tablewrap"><table>
  <thead><tr><th>Chapter</th><th>Length</th><th>Focus</th><th>Sources</th>${status ? "<th>Status</th>" : ""}</tr></thead>
  <tbody>${VIDEO.chapters.map((c) => `<tr><td>${c.n}. ${c.title}</td><td class="num">${c.minutes}</td><td>${c.focus}</td><td class="mono">${c.sources}</td>${status ? `<td>${status(c)}</td>` : ""}</tr>`).join("")}</tbody></table></div>`;

const commentBox = (target, id) => `
  <div class="cmt">
    <div class="chips" role="group" aria-label="What to change">${[
      "Colours",
      "Theme",
      "This scene",
    ]
      .map(
        (k, i) =>
          `<span class="chip pick${i === 0 ? " on" : ""}" data-kind="${k}" data-for="${id}">${k}</span>`,
      )
      .join("")}</div>
    <textarea id="${id}" placeholder="Ask for a change, e.g. warmer red, or cut the hum here"></textarea>
    <div class="row"><button class="small" data-add="${id}" data-target="${esc(target)}">Add comment</button></div>
    <div class="cmts">${st.comments
      .filter((c) => c.target === target)
      .map((c) => `<div><b>${c.kind}:</b> ${esc(c.text)}</div>`)
      .join("")}</div>
  </div>`;

const header = () => `
  <div class="proto-note"><b>Prototype, throwaway.</b> Three shapes for the one approval stop before a creative video renders. Flip with the bar at the bottom or the arrow keys. The example video and its frames are rough stand-ins; react to the shape.</div>
  <div class="head"><div><div class="eyebrow">Storyboard</div><h1>${VIDEO.title}</h1></div>
  <div class="meta"><span>${VIDEO.length}</span><span>${VIDEO.chapters.length} chapters</span><span>${VIDEO.lang}</span></div></div>`;

function logBlock(obj) {
  return `<details class="panel"><summary class="eyebrow">What the agent records (state)</summary><pre class="log">${esc(JSON.stringify(obj, null, 2))}</pre></details>`;
}

// ---------- Variant A: one page, one stop ----------
function renderA() {
  const d = st.dir,
    D = DIRS[d],
    approved = st.approved.all;
  const others = DIR_ORDER.filter((k) => k !== d);
  return `${header()}
  <section class="panel">
    <div class="row" style="justify-content:space-between"><h2>Direction: ${D.name}</h2>
      <div class="row">${D.rec ? '<span class="badge b-rec">Recommended</span>' : ""}${D.bold ? '<span class="badge b-bold">Bold</span>' : ""}<span class="badge b-wait">${D.kind}</span></div></div>
    <p>${D.pitch}</p><p class="muted">${D.why} ${D.breaks}</p>
    <div class="contact">${SCENES[1].map((s) => `<figure>${frame(d, s)}<figcaption>${s.title} <span class="muted mono">${s.t}</span></figcaption></figure>`).join("")}</div>
    ${kitBlock(d)}
  </section>
  <section class="panel"><h3>Or another direction</h3><p class="muted">Each shown as one frame. Switching re-authors chapter 1 in that look (about 12 minutes) and brings this page back.</p>
    <div class="grid3">${others.map((k) => `<div class="dir">${frame(k, SCENES[1][3])}<div class="row"><b>${DIRS[k].name}</b><span class="badge b-wait">${DIRS[k].kind}</span></div><p>${DIRS[k].pitch}</p><div class="row"><button class="small" data-dir="${k}">Use this direction</button></div></div>`).join("")}</div>
  </section>
  <section class="panel"><h3>Chapter plan</h3>${planTable()}</section>
  <section class="panel"><h3>Comments</h3>${commentBox("whole video", "cA")}
    ${
      approved
        ? `<div class="done-banner">Approved. Chapter 1 renders now; chapters 2 and 3 are authored in this look and render without another stop.</div>`
        : `<div class="row"><button class="primary" data-approve="all">Approve this look for the whole video</button><span class="muted">One stop. Comments are applied first, then the page comes back only if the look changed.</span></div>`
    }
  </section>
  ${logBlock({ variant: "A one stop", direction: d, recommended: "switch", stops_total: 1, approval_covers: "every chapter", comments: st.comments, next: approved ? "render ch1, author ch2..3 in parallel" : "wait for owner" })}`;
}

// ---------- Variant B: words first, then chapter 1 scenes ----------
function renderB() {
  const d = st.dir;
  if (!st.pickedB)
    return `${header()}
    <div class="steps"><span class="step on">1. Pick a direction</span><span class="step">2. Approve chapter 1's look</span></div>
    <section class="panel"><h2>Three directions, in words</h2><p class="muted">Nothing is authored yet, so this stop is cheap. One word ("yours") takes the recommendation.</p>
      <div class="grid3">${DIR_ORDER.map((k) => {
        const D = DIRS[k];
        return `<div class="dir${D.rec ? " on" : ""}">
        <div class="row">${D.rec ? '<span class="badge b-rec">Recommended</span>' : ""}${D.bold ? '<span class="badge b-bold">Bold</span>' : ""}<span class="badge b-wait">${D.kind}</span></div>
        <h3>${D.name}</h3><p>${D.pitch}</p><p class="muted">${D.why}</p><p class="muted">${D.breaks}</p>
        <div class="chips">${D.palette.map(([n, c]) => `<span class="chip"><span class="sw" style="background:${c}"></span>${n}</span>`).join("")}</div>
        <div class="row"><button class="${D.rec ? "primary" : ""}" data-pickb="${k}">${D.rec ? "Go with yours" : "Pick this one"}</button></div></div>`;
      }).join("")}</div>
    </section>
    ${logBlock({ variant: "B words then scenes", stop: 1, authored: "nothing yet", next: "owner picks a direction" })}`;
  const D = DIRS[d],
    approved = st.approved.all;
  return `${header()}
    <div class="steps"><span class="step done">1. ${D.name}</span><span class="step on">2. Approve chapter 1's look</span></div>
    <div class="split">
      <aside class="rail" aria-label="Chapter plan">${VIDEO.chapters.map((c) => `<div class="ch${c.n === 1 ? " on" : ""}"><b>${c.n}. ${c.title}</b><span class="muted">${c.minutes} · ${c.n === 1 ? "on this board" : "follows this look"}</span><span class="muted">${c.focus}</span></div>`).join("")}</aside>
      <section class="panel"><div class="row" style="justify-content:space-between"><h2>Chapter 1: ${VIDEO.chapters[0].title}</h2><span class="badge b-wait">5 scenes · 4:00</span></div>
        <div>${SCENES[1]
          .map(
            (
              s,
              i,
            ) => `<div class="scene">${frame(d, s)}<div class="body"><div class="row"><b>${s.title}</b><span class="mono muted">${s.t}</span></div><p class="narr">${s.narr}</p><p class="notes">${s.notes}</p>
          <details><summary class="muted" style="font-size:13px">Comment on this scene</summary>${commentBox("ch1 scene " + (i + 1), "cB" + i)}</details></div></div>`,
          )
          .join("")}</div>
        <h3>Format kit</h3>${kitBlock(d)}
        <h3>Comments on the whole look</h3>${commentBox("whole video", "cBall")}
        ${
          approved
            ? `<div class="done-banner">Approved. Chapter 1 renders; chapters 2 and 3 follow this look with no further stop unless the kit changes.</div>`
            : `<div class="row"><button class="primary" data-approve="all">Approve chapter 1's look for the whole video</button></div>`
        }
      </section>
    </div>
    ${logBlock({ variant: "B words then scenes", direction: d, stops_total: 2, approval_covers: "every chapter (kit shared)", comments: st.comments, next: approved ? "render ch1, author ch2..3 in parallel" : "wait for owner" })}`;
}

// ---------- Variant C: a board per chapter ----------
function renderC() {
  const d = st.dir,
    tab = st.cTab;
  const status = (n) =>
    st.approved[n]
      ? "approved"
      : n === 1 || st.ch2ready
        ? "awaiting you"
        : "authoring";
  const badge = (s) =>
    `<span class="badge ${s === "approved" ? "b-ok" : s === "awaiting you" ? "b-rec" : "b-wait"}">${s}</span>`;
  const ready = (n) => n === 1 || st.ch2ready;
  return `${header()}
    <div class="tabs" role="tablist">${VIDEO.chapters.map((c) => `<button class="tab${tab === c.n ? " on" : ""}" role="tab" data-tab="${c.n}">${c.n}. ${c.title} ${badge(status(c.n))}</button>`).join("")}</div>
    ${
      tab === 1
        ? `<section class="panel"><h3>Direction for the video</h3><p class="muted">Picked on chapter 1's board only; later boards inherit it.</p>
      <div class="grid3">${DIR_ORDER.map((k) => `<div class="dir${k === d ? " on" : ""}">${frame(k, SCENES[1][0])}<div class="row"><b>${DIRS[k].name}</b>${DIRS[k].rec ? '<span class="badge b-rec">Recommended</span>' : ""}${DIRS[k].bold ? '<span class="badge b-bold">Bold</span>' : ""}</div><p>${DIRS[k].pitch}</p>${k === d ? "" : `<div class="row"><button class="small" data-dir="${k}">Use this</button></div>`}</div>`).join("")}</div></section>`
        : ""
    }
    ${
      ready(tab)
        ? `<section class="panel"><div class="row" style="justify-content:space-between"><h2>Chapter ${tab}: ${VIDEO.chapters[tab - 1].title}</h2><span class="badge b-wait">${SCENES[tab].length} scenes · ${VIDEO.chapters[tab - 1].minutes}</span></div>
      <p class="muted">${VIDEO.chapters[tab - 1].focus}. Sources: ${VIDEO.chapters[tab - 1].sources}</p>
      ${SCENES[tab]
        .map(
          (
            s,
            i,
          ) => `<div class="scene" style="grid-template-columns:1fr"><div class="row"><b>${s.title}</b><span class="mono muted">${s.t}</span></div>
        <div class="strip">${["in", "key", "out"].map((p) => `<div>${frame(d, s, p)}<div class="t">${p}</div></div>`).join("")}</div>
        <p class="narr">${s.narr}</p><p class="notes">${s.notes}</p>
        <details><summary class="muted" style="font-size:13px">Comment on this scene</summary>${commentBox(`ch${tab} scene ${i + 1}`, `cC${tab}_${i}`)}</details></div>`,
        )
        .join("")}
      ${st.approved[tab] ? `<div class="done-banner">Chapter ${tab} approved; it renders now.</div>` : `<div class="row"><button class="primary" data-approve="${tab}">Approve chapter ${tab}</button>${tab > 1 ? `<button data-approve="rest">Approve all remaining chapters</button>` : ""}</div>`}
    </section>`
        : `<section class="panel"><h2>Chapter ${tab} is being authored</h2><p class="muted">Its board appears when its subagent finishes. Nothing in it renders before you approve.</p><div class="row"><button data-sim="1">Simulate: chapters 2 and 3 authored</button></div></section>`
    }
    <section class="panel"><h3>Chapter plan</h3>${planTable((c) => badge(status(c.n)))}</section>
    <section class="panel"><h3>Format kit</h3>${kitBlock(d)}</section>
    ${logBlock({ variant: "C board per chapter", direction: d, stops_total: VIDEO.chapters.length, approved: st.approved, comments: st.comments, next: "render each chapter as it is approved" })}`;
}

// ---------- wiring ----------
const VARIANTS = [
  ["a", "A · One page, one stop", renderA],
  ["b", "B · Words first, then chapter 1", renderB],
  ["c", "C · A board per chapter", renderC],
];
const app = document.getElementById("app");
function render() {
  const v = VARIANTS.find((x) => x[0] === st.variant) || VARIANTS[0];
  app.innerHTML = v[2]();
  document.getElementById("vlabel").textContent = v[1];
}
function go(step) {
  const i = VARIANTS.findIndex((x) => x[0] === st.variant);
  const nv = VARIANTS[(i + step + VARIANTS.length) % VARIANTS.length][0];
  resetFor(nv);
  try {
    history.replaceState(null, "", "#" + nv);
  } catch (e) {}
  render();
  window.scrollTo(0, 0);
}
document.getElementById("prev").onclick = () => go(-1);
document.getElementById("next").onclick = () => go(1);
document.addEventListener("keydown", (e) => {
  const t = e.target;
  if (t.closest && t.closest("input, textarea, select, [contenteditable]"))
    return;
  if (e.key === "ArrowLeft") go(-1);
  if (e.key === "ArrowRight") go(1);
});
app.addEventListener("click", (e) => {
  const b = e.target.closest(
    "[data-dir],[data-pickb],[data-approve],[data-tab],[data-sim],[data-add],.chip.pick",
  );
  if (!b) return;
  if (b.matches(".chip.pick")) {
    b.parentNode
      .querySelectorAll(".chip.pick")
      .forEach((c) => c.classList.toggle("on", c === b));
    return;
  }
  if (b.dataset.dir) {
    st.dir = b.dataset.dir;
    st.approved = {};
  }
  if (b.dataset.pickb) {
    st.dir = b.dataset.pickb;
    st.pickedB = true;
  }
  if (b.dataset.tab) st.cTab = +b.dataset.tab;
  if (b.dataset.sim) st.ch2ready = true;
  if (b.dataset.approve) {
    const a = b.dataset.approve;
    if (a === "rest")
      VIDEO.chapters.forEach((c) => {
        if (c.n > 1) st.approved[c.n] = true;
      });
    else st.approved[a] = true;
  }
  if (b.dataset.add) {
    const ta = document.getElementById(b.dataset.add),
      text = ta.value.trim();
    if (!text) return;
    const on = b.closest(".cmt").querySelector(".chip.pick.on");
    st.comments.push({
      target: b.dataset.target,
      kind: on ? on.dataset.kind : "Colours",
      text,
    });
  }
  render();
});
const h = (location.hash || "").slice(1);
if (VARIANTS.some((x) => x[0] === h)) st.variant = h;
render();

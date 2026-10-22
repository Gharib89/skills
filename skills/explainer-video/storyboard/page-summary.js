// The panels that sum the board up, drawn from the board document alone: the
// overview of every poster and the first-render estimate. A classic script
// loaded after page-core.js, whose helpers (esc, mediaUrl, needs) it shares.

// The board's first screen: every poster, and how many cards are rich, carry a finding or changed.
function overview(b) {
  const n = (f) => b.scenes.filter(f).length;
  const count = (k, label, v) =>
    `<span class="tag" data-count="${k}"><b>${v}</b> ${label}</span>`;
  return `<section class="overview panel" id="overview"><span class="label">Overview</span>
    <div class="row">${count(
      "rich",
      "rich",
      n((c) => c.rich),
    )}${count(
      "finding",
      "with a finding",
      n((c) => c.finding),
    )}${count("changed", "changed", n(needs))}</div>
    <div class="grid">${b.scenes
      .map(
        (c) =>
          `<a class="thumb${c.finding ? " flagged" : ""}" href="#card-${esc(c.id)}"><img alt="" src="${esc(mediaUrl(c.still))}"><span class="label" dir="auto">${esc(c.title)}</span></a>`,
      )
      .join("")}</div></section>`;
}
// Seconds as `6 min 30 s`, the seconds left out of whole minutes.
function span(s) {
  const whole = Math.round(s),
    m = Math.floor(whole / 60),
    r = whole - m * 60;
  return m ? `${m} min${r ? ` ${r} s` : ""}` : `${r} s`;
}
// The first-render estimate: a warning, amber above the budget, never a lock on the board.
function estimatePanel(b) {
  const e = b.estimate;
  return `<section class="estimate panel" data-over="${e.over}"><span class="label">Render estimate</span>
    <div class="row"><span class="tag${e.over ? " warn" : ""}"><b>${span(e.seconds)}</b> ${e.over ? "over" : "within"} a ${span(e.budget)} budget</span>
    <span class="label">First render only, from rates measured on HyperFrames ${esc(e.hyperframes)}.</span>${e.aceStepUnmeasured ? `\n    <span class="label">ace-step is not measured, so this leaves its score out.</span>` : ""}</div></section>`;
}

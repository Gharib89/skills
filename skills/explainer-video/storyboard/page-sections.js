/* ---- sections: a long video's cards grouped under a heading per section, each heading playing its own stretch. No DOM here either. ---- */
// The board's sections in order, as {n, title, from, to, cards}: `from` is the first scene's start, `to` the next
// section's (null for the last, which plays to the video's end). A script with no openers has none.
function sectionsOf(b) {
  const out = [];
  for (const c of b.scenes) {
    let g = out[out.length - 1];
    if (c.section && (!g || g.n !== c.section)) {
      if (g) g.to = c.start;
      out.push(
        (g = { n: c.section, title: "", from: c.start, to: null, cards: [] }),
      );
    }
    if (g) {
      g.cards.push(c);
      if (c.role === "section") g.title = c.title;
    }
  }
  return out;
}
function sectionHead(g) {
  return `<div class="sec-head"><h2 class="sec-title" dir="auto">Section ${esc(g.n)}: ${esc(g.title)}</h2><button class="btn btn-sm accent" data-act="play-section" data-section="${esc(g.n)}">Play section</button></div>`;
}
// The cards, under their section's heading when the video has sections.
function cardList(S, b) {
  const secs = sectionsOf(b);
  return secs.length
    ? secs
        .map((g) => sectionHead(g) + g.cards.map((c) => card(S, b, c)).join(""))
        .join("")
    : b.scenes.map((c) => card(S, b, c)).join("");
}

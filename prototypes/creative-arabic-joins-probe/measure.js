// Runs in the page at a sample frame. For one Arabic text box it sets a copy at
// rest (motion stripped, letters' boxes kept) beside the same words set
// unsplit in the same face, and reports per word: both advance widths, both
// rects for the pixel crop, and the copy's shaping runs (text split at every
// box that is not inline, which is where the browser shapes alone).
window.__arabicJoins = (id) => {
  const box = document.getElementById(id);
  const cs = getComputedStyle(box);
  let ov = document.getElementById("__ov");
  if (!ov) {
    ov = document.createElement("div");
    ov.id = "__ov";
    ov.style.cssText =
      "position:fixed;inset:0;background:#fff;z-index:2147483647;";
    document.body.append(ov);
  }
  ov.innerHTML = "";
  const FONT = [
    "fontFamily",
    "fontSize",
    "fontWeight",
    "fontStyle",
    "fontStretch",
    "fontFeatureSettings",
    "fontVariationSettings",
    "fontKerning",
    "letterSpacing",
    "wordSpacing",
    "lineHeight",
    "textRendering",
  ];
  const clone = box.cloneNode(true);
  clone.removeAttribute("id");
  for (const el of [clone, ...clone.querySelectorAll("*")]) {
    const s = el.style;
    s.transform =
      s.translate =
      s.rotate =
      s.scale =
      s.filter =
      s.animation =
      s.transition =
        "none";
    s.opacity = "1";
    s.visibility = "visible";
    s.color = "#000";
  }
  for (const p of FONT) clone.style[p] = cs[p];
  Object.assign(clone.style, {
    position: "absolute",
    left: "20px",
    top: "20px",
    width: cs.width,
    direction: cs.direction,
  });
  ov.append(clone);

  // Every character of the copy, with its node and offset; ZWJ kept out of
  // the logical text the words are cut from.
  const chars = [];
  const walk = document.createTreeWalker(clone, NodeFilter.SHOW_TEXT);
  for (let n = walk.nextNode(); n; n = walk.nextNode())
    for (let o = 0; o < n.data.length; o++) chars.push({ n, o, c: n.data[o] });
  const atomic = (node) => {
    for (let el = node.parentElement; el && el !== clone; el = el.parentElement)
      if (getComputedStyle(el).display !== "inline") return el;
    return clone;
  };
  // A word ends at white space, or where two boxes stand apart (a flex gap,
  // a margin) by more than a tenth of the face's size: letters that touch
  // are one word to the reader.
  const size = parseFloat(cs.fontSize);
  const apart = (a, b) => {
    const r = a.getBoundingClientRect(),
      q = b.getBoundingClientRect();
    return Math.max(r.left - q.right, q.left - r.right) > size / 10;
  };
  const words = [];
  let cur = null;
  let prev = null;
  for (const ch of chars) {
    if (/\s/.test(ch.c)) {
      cur = null;
      continue;
    }
    const box = atomic(ch.n);
    if (cur && prev !== box && apart(prev, box)) cur = null;
    prev = box;
    if (!cur) words.push((cur = []));
    cur.push(ch);
  }
  const ref = document.createElement("div");
  for (const p of FONT) ref.style[p] = cs[p];
  Object.assign(ref.style, {
    position: "absolute",
    left: "20px",
    width: cs.width,
    direction: "rtl",
    color: "#000",
  });
  ref.lang = "ar";
  ov.append(ref);
  ref.style.top = `${20 + clone.getBoundingClientRect().height + 40}px`;
  const refSpans = words.map((w) => {
    const s = document.createElement("span");
    s.textContent = w
      .map((x) => x.c)
      .join("")
      .replace(/‍/g, "");
    ref.append(s, "  ");
    return s;
  });
  const rect = (r) => ({ x: r.x, y: r.y, w: r.width, h: r.height });
  return words.map((w, i) => {
    const range = document.createRange();
    range.setStart(w[0].n, w[0].o);
    range.setEnd(w.at(-1).n, w.at(-1).o + 1);
    const runs = [];
    let key = null;
    for (const ch of w) {
      const k = atomic(ch.n);
      if (k !== key) runs.push("");
      key = k;
      runs[runs.length - 1] += ch.c;
    }
    return {
      text: refSpans[i].textContent,
      runs,
      split: rect(range.getBoundingClientRect()),
      whole: rect(refSpans[i].getBoundingClientRect()),
    };
  });
};

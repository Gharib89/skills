/* The live build's own script, last in its document (live.mjs). It runs in a frame
   sandboxed to scripts alone, with no origin and no URL to fetch from, so the page
   hands it fonts and commands by postMessage and it answers the same way. It plays
   the composition the way HyperFrames seeks it: each clip shown inside its window,
   each scene's timeline at its own offset. */
(() => {
  const tls = window.__timelines;
  const clips = [...document.querySelectorAll(".clip[data-start]")].map(
    (el) => {
      const a = +el.dataset.start;
      return {
        el,
        a,
        b: a + +el.dataset.duration,
        tl: tls[el.dataset.compositionId],
      };
    },
  );
  const show = (t) => {
    for (const c of clips) {
      c.el.style.visibility = t >= c.a && t < c.b ? "visible" : "hidden";
      c.tl?.time(Math.max(0, t - c.a), true);
    }
    tls.main.time(t, true);
  };

  let raf = 0;
  // `from` to `to` in the composition's seconds on this frame's own clock: looped,
  // or once and then held at `to` with `done` sent.
  const run = (from, to, loop) => {
    cancelAnimationFrame(raf);
    const t0 = performance.now();
    const step = (now) => {
      const t = from + (now - t0) / 1000;
      if (loop) show(from + ((t - from) % (to - from)));
      else if (t >= to) {
        show(to);
        parent.postMessage({ type: "done" }, "*");
        return;
      } else show(t);
      raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
  };

  const fonts = (list) =>
    Promise.all(
      list.map(async (f) =>
        document.fonts.add(
          await new FontFace(f.family, f.data, {
            weight: String(f.weight),
            style: f.style,
          }).load(),
        ),
      ),
    ).then(() => document.fonts.ready);

  // Commands run in arrival order, after the fonts that arrived before them.
  let queue = Promise.resolve();
  addEventListener("message", ({ source, data: m }) => {
    if (source !== parent) return;
    queue = queue.then(async () => {
      if (m.type === "fonts") {
        await fonts(m.fonts);
        parent.postMessage({ type: "shown" }, "*");
      } else if (m.type === "seek") {
        cancelAnimationFrame(raf);
        show(m.t);
      } else if (m.type === "run") run(m.from, m.to, m.loop);
      else if (m.type === "css") {
        // The page's edited palette, appended after the scene's own so it wins.
        let s = document.getElementById("edits");
        if (!s) {
          s = document.createElement("style");
          s.id = "edits";
          document.head.append(s);
        }
        s.textContent = m.css;
      }
    });
  });
  show(0);
  parent.postMessage({ type: "ready" }, "*");
})();

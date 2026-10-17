// Direction B, Velocity Cut: a locked camera, glass over a soft colour field, blur-matched seams.
DIRECTIONS.push({
  key: 'B', name: 'Velocity Cut', tagline: 'Glass cards, words that rise, seams that carry speed through the cut',
  summary: 'Each scene is a locked frame of glass cards over a soft colour field, with one push-in on its strongest cue. Words rise into place as they are spoken. Scenes hand over at speed: a zoom-through when the topic changes, and a cut-the-curve when the idea continues.',
  axes: {
    camera: 'Locked. Exactly one push-in per scene, on its cue (1.06 to 1.1 over 1.4 s, power3.inOut), then held.',
    seams: 'Hook to trails is a zoom-through: the exit scales to 1.2 with 18 px blur in 0.2 s, and the entry settles from 0.75 under expo.out. Trails to integrate is a cut-the-curve: the exit throws left with 8 px blur, and the entry keeps sliding left and decelerates.',
    type: 'Masked per-word rise (yPercent 115 to 0, power4.out, 0.05 s stagger), timed to each spoken word where it is the narration. The hook title resolves out of a 24 px blur.',
    texture: 'A static field of blurred profile hues per scene, frosted glass cards (backdrop blur 26 px), depth-of-field blur on whatever is off focus, a fixed grain and a vignette as the grade.',
    threeD: 'None.',
  },
  refs: [
    { label: 'HyperFrames FRAME.md launch film', url: 'https://static.heygen.ai/hyperframes-oss/docs/images/showcase/launch-frame-md-launch-storyboard-v1-s.mp4', what: 'zoom-through and cut-the-curve seams, velocity-matched' },
    { label: 'Linear, end card', url: 'https://youtu.be/mRql2VJ99gM?t=46', what: 'a title resolving out of blur' },
    { label: 'Linear, tilted UI', url: 'https://youtu.be/mRql2VJ99gM?t=9', what: 'glass surfaces, the far edge out of focus' },
  ],
  rtl: 'Words rise whole, so Arabic joins hold. Mirror the cut-the-curve (the exit throws right and the entry slides in from the left), the card order and the arc. The zoom-through and blur-in are direction-neutral.',
  composer: 'New: a seam per scene boundary on the root timeline (the outgoing scene runs 0.2 to 0.3 s past its slot), a word-timed rise helper, glass and field components, and a grain and vignette grade. backdrop-filter and large blurs cost paint time per frame, so render time needs measuring; the grain is static, so determinism holds.',
  scenes: {
    hook: 'The question rises word by word as it is spoken. The title resolves out of blur, then lifts to the top. Two glass cards hold the five delivery metrics: high bars for top performers, low ones for low performers, with one push-in on "five". The model\'s three columns close the scene.',
    trails: 'Enters on a zoom-through. Three numbered glass cards rise on their cues. A red churn pill shakes the first card. The push-in lands on "evergreen", blurring the first two cards out of focus. An arc from research to Core closes it.',
    integrate: 'Enters on a cut-the-curve. A glass terminal prints each line word by word: the regression line in red, then a "fixed" chip. Test driven development sits beside it, and the push-in lands on the under-10-minutes line.',
  },
  css: `
.dir-b .sc { position: absolute; inset: 0; }
.dir-b .fld { position: absolute; inset: -360px; background: #fff; overflow: hidden; }
.dir-b .cam { position: absolute; inset: 0; transform-origin: 50% 50%; }
.dir-b .blob { position: absolute; border-radius: 50%; filter: blur(110px); }
.dir-b .glass { position: absolute; border-radius: 36px; background: rgba(255,255,255,.46); border: 2px solid rgba(255,255,255,.75); box-shadow: 0 30px 80px rgba(32,33,36,.12), inset 0 1px 0 rgba(255,255,255,.9); backdrop-filter: blur(26px) saturate(1.15); -webkit-backdrop-filter: blur(26px) saturate(1.15); }
.dir-b .m { display: inline-block; overflow: hidden; vertical-align: bottom; padding: 0 .02em .1em; margin-bottom: -.1em; }
.dir-b .w { display: inline-block; }
.dir-b .q { position: absolute; left: 210px; top: 330px; width: 1500px; font: 600 84px/1.18 var(--ft); letter-spacing: -.015em; }
.dir-b .kick { font: 600 40px var(--ft); color: var(--accent); margin-bottom: 18px; }
.dir-b .title { position: absolute; left: 0; right: 0; top: 340px; text-align: center; transform-origin: 50% 0; }
.dir-b .title .big { font: 600 100px/1.05 var(--ft); letter-spacing: -.02em; }
.dir-b .hl { background: linear-gradient(transparent 62%, var(--chip) 62%); background-size: 0% 100%; background-repeat: no-repeat; }
.dir-b .pill { position: absolute; padding: 18px 40px; border-radius: 999px; font: 600 44px var(--ft); white-space: nowrap; }
.dir-b .card h3 { margin: 0; font: 600 44px var(--ft); }
.dir-b .row { margin-top: 22px; }
.dir-b .row .n { font: 400 28px var(--ft); color: var(--muted); }
.dir-b .row .tr { margin-top: 10px; height: 16px; border-radius: 8px; background: rgba(32,33,36,.08); overflow: hidden; }
.dir-b .row .b { height: 100%; width: 100%; border-radius: 8px; transform-origin: 0 50%; }
.dir-b .col { position: absolute; top: 470px; padding: 34px 56px; font: 600 60px var(--ft); }
.dir-b .arrow { position: absolute; font: 400 64px var(--ft); color: var(--muted); }
.dir-b .head { position: absolute; left: 150px; top: 84px; font: 600 40px var(--ft); color: var(--muted); }
.dir-b .step { padding: 44px 46px; }
.dir-b .step .ix { font: 400 30px var(--fm); color: var(--muted); }
.dir-b .step .lb { margin-top: 40px; font: 600 58px/1.08 var(--ft); letter-spacing: -.01em; }
.dir-b .step .nt { margin-top: 22px; font: 400 34px var(--ft); color: var(--muted); }
.dir-b .term { overflow: hidden; }
.dir-b .term .bar { height: 76px; display: flex; align-items: center; gap: 14px; padding: 0 34px; border-bottom: 1.5px solid rgba(255,255,255,.7); font: 400 28px var(--fm); color: var(--muted); }
.dir-b .term .bar i { width: 18px; height: 18px; border-radius: 50%; background: rgba(32,33,36,.18); display: block; }
.dir-b .term .body { padding: 44px 56px; font: 400 46px/1.85 var(--fm); }
.dir-b .term .ln { white-space: nowrap; }
.dir-b .grain { position: absolute; inset: 0; pointer-events: none; mix-blend-mode: overlay; opacity: .55; background-image: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='320' height='320'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2' stitchTiles='stitch'/><feColorMatrix values='0 0 0 0 .5  0 0 0 0 .5  0 0 0 0 .5  0 0 0 .9 0'/></filter><rect width='100%' height='100%' filter='url(%23n)'/></svg>"); }
.dir-b .vig { position: absolute; inset: 0; pointer-events: none; background: radial-gradient(ellipse at 50% 46%, transparent 55%, rgba(32,33,36,.22) 100%); }
`,
  build(frame) {
    const { el, sent, word, S } = H;
    const tl = gsap.timeline({ paused: true });
    const at = (e, x, y, w, h) => { Object.assign(e.style, { left: x + 'px', top: y + 'px' }); if (w) e.style.width = w + 'px'; if (h) e.style.height = h + 'px'; return e; };
    // masked whole words; returns the inner spans that rise
    const mw = (parent, text, cls = '') => text.split(/\s+/).map((t, i, a) => {
      const m = el(parent, 'span', 'm'), w = el(m, 'span', 'w ' + cls); w.textContent = t;
      if (i < a.length - 1) parent.appendChild(document.createTextNode(' '));
      return w;
    });
    const rise = (ws, t0, st = 0.05) => tl.fromTo(ws, { yPercent: 115 }, { yPercent: 0, duration: 0.7, ease: 'power4.out', stagger: st }, t0);
    const fadeIn = (e, t0, from = { opacity: 0, y: 40 }) => tl.fromTo(e, from, { opacity: 1, x: 0, y: 0, scale: 1, duration: 0.6, ease: 'power3.out' }, t0);
    const defocus = (e, t0, b = 6, o = 0.55) => tl.to(e, { filter: `blur(${b}px)`, opacity: o, duration: 0.6, ease: 'power2.inOut' }, t0);
    // the field overhangs the frame by 360 px so a seam's scale or slide never shows its edge
    const field = (sc, spots) => { const f = el(sc, 'div', 'fld'); spots.forEach(([x, y, r, c, o]) => { const b = el(f, 'div', 'blob'); at(b, x - r + 360, y - r + 360, 2 * r, 2 * r); b.style.background = c; b.style.opacity = o; }); };
    const A = '#2782cc', Y = '#f0e15a', G = '#558141';

    const L = { hook: el(frame, 'div', 'sc'), trails: el(frame, 'div', 'sc'), integrate: el(frame, 'div', 'sc') };
    el(frame, 'div', 'grain'); el(frame, 'div', 'vig');
    const t1 = S.trails.start, t2 = S.integrate.start;
    tl.set(L.hook, { autoAlpha: 1, filter: 'none' }, 0);
    tl.set([L.trails, L.integrate], { autoAlpha: 0 }, 0);

    /* ---------- hook ---------- */
    field(L.hook, [[260, 180, 420, A, .38], [1700, 260, 380, Y, .55], [1500, 960, 460, A, .22], [380, 980, 360, Y, .4]]);
    const hc = el(L.hook, 'div', 'cam');
    const q = el(hc, 'div', 'q');
    const qw = S.hook.words.slice(0, 17).map((w, i, a) => {
      const m = el(q, 'span', 'm'), s = el(m, 'span', 'w'); s.textContent = w.text;
      if (i >= 6 && i <= 8) s.style.color = 'var(--accent)';
      if (i >= 15) s.style.color = 'var(--stop)';
      if (i < a.length - 1) q.appendChild(document.createTextNode(' '));
      tl.fromTo(s, { yPercent: 115 }, { yPercent: 0, duration: 0.6, ease: 'power4.out' }, w.a - 0.05);
      return s;
    });
    tl.to(qw, { yPercent: -115, duration: 0.35, ease: 'power2.in', stagger: 0.012 }, sent('hook', 2) - 0.25);

    const title = el(hc, 'div', 'title');
    el(title, 'div', 'kick', 'DORA Core');
    const big = el(title, 'div', 'big', 'Speed and stability are <span class="hl">not tradeoffs</span>');
    tl.fromTo(title, { opacity: 0, filter: 'blur(24px)', scale: 1.08 }, { opacity: 1, filter: 'blur(0px)', scale: 1, duration: 1.3, ease: 'expo.out' }, sent('hook', 2) + 0.2);
    tl.to(big.querySelector('.hl'), { backgroundSize: '100% 100%', duration: 0.5, ease: 'power2.out' }, word('hook', 'not'));
    tl.to(title, { y: -250, scale: 0.6, duration: 1, ease: 'power3.inOut' }, sent('hook', 3));

    const corr = el(hc, 'div', 'glass pill'); at(corr, 0, 480); corr.style.fontSize = '64px'; corr.style.padding = '26px 60px'; corr.style.left = '50%'; corr.style.transform = 'translateX(-50%)';
    rise(mw(corr, 'The metrics are correlated'), sent('hook', 3) + 0.4, 0.08);
    fadeIn(corr, sent('hook', 3) + 0.3, { opacity: 0, y: 30 });
    tl.to(corr, { opacity: 0, filter: 'blur(10px)', duration: 0.5, ease: 'power2.in' }, sent('hook', 4) - 0.2);

    const metrics = ['Deployment frequency', 'Change lead time', 'Change fail rate', 'Failed deployment recovery time', 'Rework rate'];
    const rnd = H.rng(11);
    const cards = [['Top performers', A, 0.82, 'well', 230], ['Low performers', '#b84b33', 0.2, 'low', 1010]].map(([name, c, lvl, cue, x]) => {
      const card = at(el(hc, 'div', 'glass card'), x, 380, 680);
      card.style.padding = '40px 50px 46px';
      const h = el(card, 'h3'); rise(mw(h, name), sent('hook', 4) + (x > 500 ? 0.25 : 0.1));
      metrics.forEach((m, i) => {
        const r = el(card, 'div', 'row'); el(r, 'div', 'n', m);
        const b = el(el(r, 'div', 'tr'), 'div', 'b'); b.style.background = c;
        tl.fromTo(b, { scaleX: 0 }, { scaleX: lvl + rnd() * 0.12, duration: 0.8, ease: 'power3.out' }, word('hook', cue) + i * 0.09);
      });
      fadeIn(card, sent('hook', 4) + (x > 500 ? 0.15 : 0));
      return card;
    });
    tl.fromTo(hc, { scale: 1 }, { scale: 1.06, transformOrigin: '960px 560px', duration: 1.4, ease: 'power3.inOut' }, word('hook', 'five'));
    defocus(cards, sent('hook', 5), 8, 0.35); defocus(title, sent('hook', 5), 6, 0.4);
    const cols = ['Capabilities', 'Performance', 'Outcomes'];
    const cw = [520, 540, 460], cx = [190, 760, 1350];
    cols.forEach((c, i) => {
      const col = at(el(hc, 'div', 'glass col'), cx[i] - 30, 470); col.style.top = '470px';
      rise(mw(col, c), [word('hook', 'whole'), word('hook', 'piece'), word('hook', 'piece', 1)][i]);
      fadeIn(col, [word('hook', 'whole'), word('hook', 'piece'), word('hook', 'piece', 1)][i] - 0.1, { opacity: 0, y: 60 });
      if (i) { const ar = at(el(hc, 'div', 'arrow', '→'), cx[i] - 92, 498); fadeIn(ar, [0, word('hook', 'piece'), word('hook', 'piece', 1)][i] - 0.15, { opacity: 0, y: 0 }); }
    });

    // seam 1: zoom-through
    tl.fromTo(L.hook, { scale: 1, filter: 'blur(0px)' }, { scale: 1.2, filter: 'blur(18px)', duration: 0.2, ease: 'power3.in', immediateRender: false }, t1 - 0.2);
    tl.set(L.hook, { autoAlpha: 0 }, t1);
    tl.set(L.trails, { autoAlpha: 1 }, t1);
    tl.fromTo(L.trails, { scale: 0.75, filter: 'blur(18px)' }, { scale: 1, filter: 'blur(0px)', duration: 0.6, ease: 'expo.out', immediateRender: false }, t1);
    tl.set(L.trails, { filter: 'none' }, t1 + 0.61);

    /* ---------- trails ---------- */
    field(L.trails, [[1650, 160, 440, A, .34], [200, 860, 420, Y, .5], [1100, 1060, 380, G, .2], [700, 120, 300, Y, .3]]);
    const tc = el(L.trails, 'div', 'cam');
    const th = el(tc, 'div', 'head'); mw(th, 'Why Core moves slowly');
    const steps = H.props.trails.steps;
    const xs = [150, 710, 1270];
    const SC = steps.map((s, i) => {
      const c = at(el(tc, 'div', 'glass step'), xs[i], 360, 500, 400);
      if (i === 2) { c.style.borderColor = 'rgba(85,129,65,.55)'; c.style.background = 'rgba(234,243,229,.55)'; }
      el(c, 'div', 'ix', String(i + 1).padStart(2, '0'));
      const lb = el(c, 'div', 'lb'), nt = el(c, 'div', 'nt');
      const t0 = sent('trails', s.at);
      fadeIn(c, i ? t0 : t1, { opacity: 0, y: 80, scale: 0.96 });
      rise(mw(lb, s.label), t0 + 0.15); rise(mw(nt, s.note), t0 + 0.35, 0.04);
      if (i) { const ar = at(el(tc, 'div', 'arrow', '→'), xs[i] - 50, 520); ar.style.fontSize = '44px'; fadeIn(ar, t0, { opacity: 0, y: 0 }); }
      return c;
    });
    const churn = at(el(tc, 'div', 'pill'), 300, 230); churn.style.background = 'var(--stop)'; churn.style.color = '#fff';
    fadeIn(churn, word('trails', 'churn') - 0.6, { opacity: 0, y: 30 });
    rise(mw(churn, 'counterproductive churn'), word('trails', 'churn') - 0.5, 0.1);
    for (let i = 0; i < 6; i++) tl.to(SC[0], { rotation: i % 2 ? -2.2 : 2.2, x: i % 2 ? -10 : 10, duration: 0.09, ease: 'sine.inOut' }, word('trails', 'churn') + i * 0.09);
    tl.to(SC[0], { rotation: 0, x: 0, duration: 0.2 }, word('trails', 'churn') + 0.54);
    tl.to(churn, { opacity: 0, filter: 'blur(10px)', duration: 0.5 }, sent('trails', 4));
    tl.to(tc, { scale: 1.08, transformOrigin: '1250px 560px', duration: 1.4, ease: 'power3.inOut' }, word('trails', 'evergreen'));
    defocus(SC.slice(0, 2), word('trails', 'evergreen'), 6, 0.6);
    tl.to(SC.slice(0, 2), { filter: 'blur(0px)', opacity: 1, duration: 0.6 }, sent('trails', 5));
    const arc = el(tc, 'div'); at(arc, 0, 0, 1920, 1080); arc.style.position = 'absolute';
    arc.innerHTML = '<svg width="1920" height="1080" style="position:absolute;inset:0;overflow:visible"><path d="M400 352 C 520 200, 1400 200, 1520 352" fill="none" stroke="#558141" stroke-width="6" stroke-linecap="round" stroke-dasharray="1400" stroke-dashoffset="1400"/></svg>';
    tl.to(arc.querySelector('path'), { strokeDashoffset: 0, duration: 1.1, ease: 'power2.inOut' }, sent('trails', 5) + 0.2);
    const ev = at(el(tc, 'div', 'glass pill'), 0, 196); ev.style.left = '50%'; ev.style.transform = 'translateX(-50%)'; ev.style.fontSize = '36px'; ev.style.padding = '12px 32px';
    fadeIn(ev, word('trails', 'evolves'), { opacity: 0, y: 20 });
    rise(mw(ev, 'evolves with it, more slowly'), word('trails', 'evolves') + 0.1, 0.06);

    // seam 2: cut-the-curve
    tl.fromTo(L.trails, { xPercent: 0, filter: 'blur(0px)' }, { xPercent: -13, filter: 'blur(8px)', duration: 0.3, ease: 'power2.in', immediateRender: false }, t2 - 0.3);
    tl.set(L.trails, { autoAlpha: 0 }, t2);
    tl.set(L.integrate, { autoAlpha: 1 }, t2);
    tl.fromTo(L.integrate, { xPercent: 13, filter: 'blur(8px)' }, { xPercent: 0, filter: 'blur(0px)', duration: 0.75, ease: 'power4.out', immediateRender: false }, t2);
    tl.set(L.integrate, { filter: 'none' }, t2 + 0.76);

    /* ---------- integrate ---------- */
    field(L.integrate, [[300, 260, 420, Y, .5], [1700, 900, 460, A, .32], [1650, 180, 300, G, .2], [700, 1040, 340, A, .2]]);
    const ic = el(L.integrate, 'div', 'cam');
    const ih = el(ic, 'div', 'head'); mw(ih, 'Integration and tests');
    const term = at(el(ic, 'div', 'glass term'), 150, 230, 1180, 560);
    term.innerHTML = '<div class="bar"><i></i><i></i><i></i><span style="margin-left:16px">every check in</span></div><div class="body"></div>';
    fadeIn(term, t2 + 0.1, { opacity: 0, y: 0 });
    const body = term.querySelector('.body');
    const lines = [['$ git push', sent('integrate', 1) + 0.2, 'var(--text)'], ['running quick tests', word('integrate', 'quick'), 'var(--muted)'],
      ['regression found: fix it now', word('integrate', 'regressions'), 'var(--stop)'], ['feedback in under 10 minutes', word('integrate', 'feedback'), 'var(--ok)']];
    const LN = lines.map(([text, t0, c]) => { const ln = el(body, 'div', 'ln'); ln.style.color = c; rise(mw(ln, text), t0, 0.07); return ln; });
    const fixed = at(el(ic, 'div', 'pill'), 1050, 538); Object.assign(fixed.style, { background: 'var(--ok)', color: '#fff', fontSize: '30px', padding: '8px 24px' });
    fadeIn(fixed, word('integrate', 'immediately'), { opacity: 0, y: 0, scale: 0.6 });
    rise(mw(fixed, 'fixed'), word('integrate', 'immediately') + 0.1);
    const tdd = at(el(ic, 'div', 'glass pill'), 1390, 300); Object.assign(tdd.style, { fontSize: '42px', whiteSpace: 'normal', width: '440px', borderRadius: '36px', lineHeight: '1.2' });
    fadeIn(tdd, word('integrate', 'test') - 0.1, { opacity: 0, x: 40, y: 0 });
    rise(mw(tdd, 'test driven development'), word('integrate', 'test'), 0.12);
    const ten = at(el(ic, 'div', 'glass pill'), 1390, 560); Object.assign(ten.style, { fontSize: '44px', color: 'var(--ok)' });
    fadeIn(ten, word('integrate', 'ten') - 0.1, { opacity: 0, x: 40, y: 0 });
    rise(mw(ten, '< 10 min'), word('integrate', 'ten'), 0.1);
    tl.to(ic, { scale: 1.1, transformOrigin: '760px 720px', duration: 1.4, ease: 'power3.inOut' }, word('integrate', 'feedback'));
    defocus([tdd, LN[0], LN[1]], word('integrate', 'feedback') + 0.4, 4, 0.55);
    return tl;
  },
});

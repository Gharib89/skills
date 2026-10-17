// Direction C, Word Stage: no camera and no diagrams; huge words land on the spoken word.
DIRECTIONS.push({
  key: 'C', name: 'Word Stage', tagline: 'Huge words land on the spoken word; the ground flips per scene',
  summary: 'Type carries the video. One to three heavy words hold the frame at a time, each landing on the word the narrator says. Scale stands in for the camera, a token cycle swaps one word in a fixed phrase, a drum rolls through a list, and every scene hands over with a per-word waterfall and a flip of the ground.',
  axes: {
    camera: 'None. Scale is the camera: a key word grows slowly while it holds, and a finished phrase shrinks into its place in the next layout.',
    seams: 'A waterfall: the outgoing words throw left one by one with 12 px of blur under power2.in, the incoming words keep travelling the same way and settle. The ground flips white to dark and back at each scene boundary.',
    type: 'Google Sans Flex 600 at 130 to 300 px, by whole word, rising out of a mask under power4.out. A token cycle swaps one slot of a fixed phrase ("ship quickly / safely / slowly"); a rotary drum rolls through the five delivery metrics; scale marks emphasis.',
    texture: 'None. Pure grounds: white with dark type, then dark with white type, alternating per scene.',
    threeD: 'Only the drum (CSS rotateX on one word list). No WebGL.',
  },
  refs: [
    { label: 'Apple, Don\'t Blink', url: 'https://youtu.be/jk6sz25OZgw?t=23', what: 'scale as emphasis, one word fills the frame' },
    { label: 'Raycast, launch film', url: 'https://youtu.be/Mi173xGb0ZA?t=30', what: 'token cycle: a fixed word plus one swapped slot' },
    { label: 'HeyGen x Stripe (no link)', url: 'https://www.youtube.com/results?search_query=heygen+stripe', what: 'rotary drum stepping onto spoken verbs' },
  ],
  rtl: 'Safe by construction: every move is per whole word, never per letter, so Arabic stays joined. The waterfall throws right instead of left, the token-cycle axis mirrors (slot on the left of the fixed word), and the terminal grows by whole tokens.',
  composer: 'New: a kinetic-type component that takes a phrase and per-word cue times from the word timings, plus token-cycle and drum variants. The ground flip and waterfall are root-timeline seams. Pure CSS transforms and filters, so determinism holds and renders stay cheap; text widths must be baked, not measured at run time.',
  scenes: {
    hook: '"Why" fills the frame, then a token cycle: "ship" holds while its slot rolls quickly, safely, slowly. "break things" lands in red. "speed & stability / not tradeoffs" builds by word, "correlated" grows as it holds, "Top performers" swaps to "Low performers" over a drum of the five delivery metrics, and "DORA Core" closes on "piece by piece".',
    trails: 'The ground flips dark and "DORA Core" stays, so the subject carries across the seam. It shrinks into the bottom of a three-word stack (New research, Repeated findings, DORA Core) joined by arrows. On "churn" the stack dims and "your practices" spins on a drum; then the stack returns with an "evergreen" tag.',
    integrate: 'White again, "continuous integration" fills the frame, then gives way to a terminal typed by whole token on the narration. A chip-yellow sweep marks "regression found". Above it a token cycle reads "test automation", "test driven development", then "test suites".',
  },
  css: `
.dir-c .root { position: absolute; inset: 0; color: #202124; }
.dir-c .ground { position: absolute; inset: 0; background: #ffffff; }
.dir-c .ln { position: absolute; left: 0; right: 0; text-align: center; font-weight: 600; line-height: 1; white-space: nowrap; letter-spacing: -0.025em; }
.dir-c .ln.sub { font-weight: 400; letter-spacing: 0; opacity: .62; }
.dir-c .m { display: inline-block; overflow: hidden; padding: 0.08em 0.05em 0.16em; margin: -0.08em -0.05em -0.16em; vertical-align: top; }
.dir-c .w { display: inline-block; }
.dir-c .grp { position: absolute; inset: 0; }
.dir-c .drum { position: absolute; left: 0; right: 0; height: 120px; perspective: 1400px; }
.dir-c .drum .in { position: absolute; inset: 0; transform-style: preserve-3d; }
.dir-c .drum .face { position: absolute; left: 0; right: 0; top: 0; height: 120px; text-align: center; font-weight: 600; font-size: 104px; line-height: 120px; white-space: nowrap; letter-spacing: -0.02em; backface-visibility: hidden; }
.dir-c .arrow { position: absolute; left: 50%; width: 8px; margin-left: -4px; background: currentColor; transform-origin: 50% 0; }
.dir-c .arrow::after { content: ""; position: absolute; left: -16px; bottom: -18px; border: 20px solid transparent; border-top: 24px solid currentColor; border-bottom: 0; }
.dir-c .tag { display: inline-block; padding: 14px 34px 18px; border-radius: 999px; background: var(--ok); color: #fff; }
.dir-c .term { position: absolute; left: 210px; top: 300px; width: 1500px; height: 620px; border-radius: 28px; background: #202124; color: #e8eaed; font-family: var(--fm); font-size: 58px; line-height: 1.6; padding: 110px 64px 40px; overflow: hidden; }
.dir-c .term .bar { position: absolute; left: 0; right: 0; top: 0; height: 74px; background: #2d2e31; display: flex; align-items: center; gap: 14px; padding: 0 30px; font-size: 30px; color: #9aa0a6; }
.dir-c .term .bar i { width: 18px; height: 18px; border-radius: 50%; background: #5f6368; display: block; }
.dir-c .term .tl { white-space: nowrap; }
.dir-c .term .tk { display: inline-block; opacity: 0; }
.dir-c .hl { position: relative; display: inline-block; isolation: isolate; }
.dir-c .hl .sw { position: absolute; left: -10px; right: -10px; top: 6px; bottom: 2px; background: var(--chip); z-index: -1; transform-origin: 0 50%; border-radius: 6px; }
`,
  build(frame) {
    const { el, sent, word } = H;
    const tl = gsap.timeline({ paused: true });
    const ground = el(frame, 'div', 'ground');
    const root = el(frame, 'div', 'root');
    const DARK = '#202124', LIGHT = '#ffffff';

    // a line of masked words; rise() on .w, exit on .m
    const line = (parent, text, top, size, o = {}) => {
      const d = el(parent, 'div', 'ln' + (o.sub ? ' sub' : ''));
      Object.assign(d.style, { top: top + 'px', fontSize: size + 'px' });
      if (o.color) d.style.color = o.color;
      if (o.align === 'right') Object.assign(d.style, { right: 'auto', width: o.x + 'px', textAlign: 'right' });
      if (o.align === 'left') Object.assign(d.style, { left: o.x + 'px', textAlign: 'left' });
      const m = [], w = [];
      text.split(' ').forEach((t, i, a) => {
        const mm = el(d, 'span', 'm'); const ww = el(mm, 'span', 'w'); ww.textContent = t;
        m.push(mm); w.push(ww); if (i < a.length - 1) d.appendChild(document.createTextNode(' '));
      });
      return { d, m, w };
    };
    const rise = (w, t, d = 0.6) => tl.fromTo(w, { yPercent: 118 }, { yPercent: 0, duration: d, ease: 'power4.out' }, t);
    const riseAt = (L, times) => L.w.forEach((w, i) => rise(w, times[i]));
    const sink = (w, t) => tl.to(w, { yPercent: -118, duration: 0.32, ease: 'power3.in' }, t);
    // waterfall: per-word throw with blur; dir -1 throws left
    const fall = (masks, t, dir = -1) => tl.to(masks, { x: dir * 240, opacity: 0, filter: 'blur(12px)', duration: 0.34, ease: 'power2.in', stagger: 0.045 }, t);
    // incoming words continue the same travel and settle (cut-the-curve per word)
    const carryIn = (masks, t, dir = -1) => tl.fromTo(masks, { x: -dir * 260, opacity: 0, filter: 'blur(12px)' }, { x: 0, opacity: 1, filter: 'blur(0px)', duration: 0.6, ease: 'power4.out', stagger: 0.06 }, t);
    const flip = (t, toDark) => tl.to(ground, { backgroundColor: toDark ? DARK : LIGHT, duration: 0.22, ease: 'power2.inOut' }, t)
      .to(root, { color: toDark ? LIGHT : DARK, duration: 0.22, ease: 'power2.inOut' }, t);
    const AX = 900; // token-cycle axis: fixed word ends here, slot starts here + gap

    /* ---------------- hook ---------------- */
    const why = line(root, 'Why', 390, 300);
    rise(why.w, 0.1); sink(why.w, 1.0);

    const ship = line(root, 'ship', 430, 220, { align: 'right', x: AX });
    rise(ship.w, word('hook', 'ship'));
    const slots = [['quickly', 'var(--accent)', 'quickly'], ['safely', 'var(--ok)', 'safely'], ['slowly', 'var(--muted)', 'slowly']];
    const S = slots.map(([t, c]) => line(root, t, 430, 220, { align: 'left', x: AX + 60, color: c }));
    S.forEach((L, i) => {
      rise(L.w, word('hook', slots[i][2]), 0.45);
      if (i < 2) sink(L.w, word('hook', slots[i + 1][2]) - 0.28);
    });
    const brk = line(root, 'break things', 440, 230, { color: 'var(--stop)' });
    fall([...ship.m, ...S[2].m], word('hook', 'break') - 0.3);
    riseAt(brk, [word('hook', 'break'), word('hook', 'things')]);
    tl.fromTo(brk.d, { scale: 0.86 }, { scale: 1.04, duration: 1.1, ease: 'power2.out' }, word('hook', 'break'));
    fall(brk.m, sent('hook', 2) - 0.28);

    const dr = line(root, "DORA's research", 440, 200);
    riseAt(dr, [sent('hook', 2), word('hook', 'research')]);
    fall(dr.m, word('hook', 'speed') - 0.3);

    const sp = line(root, 'speed & stability', 300, 190);
    riseAt(sp, [word('hook', 'speed'), word('hook', 'and', 2), word('hook', 'stability')]);
    const nt = line(root, 'not tradeoffs.', 560, 190, { color: 'var(--accent)' });
    riseAt(nt, [word('hook', 'not'), word('hook', 'tradeoffs')]);
    tl.fromTo(nt.d, { scale: 0.8 }, { scale: 1, duration: 0.9, ease: 'power3.out' }, word('hook', 'not'));
    fall([...sp.m, ...nt.m], sent('hook', 3) - 0.3);

    const met = line(root, 'the metrics are', 300, 84, { sub: true });
    riseAt(met, [word('hook', 'the'), word('hook', 'metrics'), word('hook', 'are', 1)]);
    const cor = line(root, 'correlated', 450, 270);
    rise(cor.w, word('hook', 'correlated'));
    tl.fromTo(cor.d, { scale: 0.84 }, { scale: 1, duration: 1.9, ease: 'power1.out' }, word('hook', 'correlated'));
    fall([...met.m, ...cor.m], sent('hook', 4) - 0.32);

    const perf = line(root, 'performers', 170, 170, { align: 'left', x: 760 });
    const top = line(root, 'Top', 170, 170, { align: 'right', x: 720, color: 'var(--accent)' });
    const low = line(root, 'Low', 170, 170, { align: 'right', x: 720, color: 'var(--stop)' });
    rise(top.w, word('hook', 'top')); rise(perf.w, word('hook', 'performers'));
    sink(top.w, word('hook', 'low') - 0.28); rise(low.w, word('hook', 'low'), 0.45);
    // rotary drum of the five delivery metrics
    const drum = el(root, 'div', 'drum'); drum.style.top = '600px';
    const din = el(drum, 'div', 'in');
    const metrics = ['deployment frequency', 'change lead time', 'change fail rate', 'failed deployment recovery time', 'rework rate'];
    const R = 300;
    const faces = metrics.map((t, i) => { const f = el(din, 'div', 'face', t); f.style.transform = `rotateX(${-i * 36}deg) translateZ(${R}px)`; return f; });
    tl.set(din, { z: -R }, 0);
    tl.fromTo(drum, { opacity: 0, y: 60 }, { opacity: 1, y: 0, duration: 0.5, ease: 'power3.out' }, word('hook', 'across'));
    tl.set(faces.slice(1), { opacity: 0.16 }, 0);
    for (let i = 1; i < 5; i++) {
      const t0 = word('hook', 'across') + i * 0.6;
      tl.to(din, { rotationX: i * 36, duration: 0.3, ease: 'power3.out' }, t0);
      tl.to(faces[i - 1], { opacity: 0.16, duration: 0.25 }, t0).to(faces[i], { opacity: 1, duration: 0.25 }, t0);
    }
    tl.to(faces, { color: 'var(--stop)', duration: 0.3 }, word('hook', 'poorly'));
    fall([...low.m, ...perf.m], sent('hook', 5) - 0.32);
    tl.to(drum, { x: -240, opacity: 0, filter: 'blur(12px)', duration: 0.34, ease: 'power2.in' }, sent('hook', 5) - 0.22);

    const whole = line(root, 'the whole', 250, 90, { sub: true });
    riseAt(whole, [word('hook', 'the', 1), word('hook', 'whole')]);
    const core = line(root, 'DORA Core', 410, 260);
    riseAt(core, [word('hook', 'dora'), word('hook', 'core')]);
    tl.fromTo(core.d, { scale: 0.9 }, { scale: 1, duration: 3.2, ease: 'power1.out' }, word('hook', 'dora'));
    const pbp = line(root, 'piece by piece', 740, 100, { sub: true });
    riseAt(pbp, [word('hook', 'piece'), word('hook', 'by'), word('hook', 'piece', 1)]);

    /* ---- seam 1: waterfall out, ground flips dark, DORA Core carries ---- */
    const B1 = H.S.trails.start;
    fall([...whole.m, ...pbp.m], B1 - 0.42);
    flip(B1 - 0.12, true);

    /* ---------------- trails ---------------- */
    const guide = line(root, 'a guide for practitioners', 740, 96, { sub: true });
    riseAt(guide, [word('trails', 'a'), word('trails', 'guide'), word('trails', 'for'), word('trails', 'practitioners')]);
    fall(guide.m, sent('trails', 2) - 0.1);
    // DORA Core shrinks into the bottom of the stack: scale is the camera
    tl.to(core.d, { y: 790 - 540, scale: 0.5, duration: 0.9, ease: 'power3.inOut' }, word('trails', 'trails'));
    const nr = line(root, 'New research', 150, 130);
    riseAt(nr, [word('trails', 'research') - 0.3, word('trails', 'research')]);
    const rf = line(root, 'Repeated findings', 450, 130);
    riseAt(rf, [word('trails', 'evolving'), word('trails', 'more')]);
    const a1 = el(root, 'div', 'arrow'); Object.assign(a1.style, { top: '310px', height: '90px' });
    const a2 = el(root, 'div', 'arrow'); Object.assign(a2.style, { top: '610px', height: '90px' });
    tl.fromTo(a1, { scaleY: 0, opacity: 0 }, { scaleY: 1, opacity: 1, duration: 0.4, ease: 'power2.out' }, word('trails', 'evolving') - 0.2);
    tl.fromTo(a2, { scaleY: 0, opacity: 0 }, { scaleY: 1, opacity: 1, duration: 0.4, ease: 'power2.out' }, word('trails', 'conservatively'));
    const stack = [nr.d, rf.d, a1, a2];
    // churn: the stack dims, "your practices" spins on a drum
    tl.to([...stack, core.d], { opacity: 0.05, filter: 'blur(8px)', duration: 0.5, ease: 'power2.out' }, sent('trails', 3));
    const yp = line(root, 'your practices', 300, 190);
    riseAt(yp, [word('trails', 'your'), word('trails', 'practices')]);
    const cc = line(root, 'counterproductive', 580, 110, { color: 'var(--stop)' });
    rise(cc.w, word('trails', 'counterproductive'));
    const ch = line(root, 'churn.', 720, 160, { color: 'var(--stop)' });
    rise(ch.w, word('trails', 'churn'), 0.4);
    tl.to(yp.d, { rotationX: 360, duration: 1.2, ease: 'steps(12)', transformPerspective: 1400 }, word('trails', 'churn'));
    fall([...yp.m, ...cc.m, ...ch.m], sent('trails', 4) - 0.2);
    tl.to([...stack, core.d], { opacity: 1, filter: 'blur(0px)', duration: 0.5, ease: 'power2.out' }, sent('trails', 4) + 0.1);
    const ev = line(root, '', 900, 64);
    ev.d.innerHTML = '<span class="m"><span class="w tag">evergreen</span></span>';
    rise(ev.d.querySelector('.w'), word('trails', 'evergreen'));
    tl.to(core.d, { scale: 0.56, duration: 0.6, ease: 'power3.out' }, word('trails', 'evergreen'));
    // "but more slowly": the arrows ease off to a slower beat
    tl.to([a1, a2], { opacity: 0.45, duration: 0.6 }, word('trails', 'slowly'));

    /* ---- seam 2: waterfall out, ground flips back, "continuous integration" carries in ---- */
    const B2 = H.S.integrate.start;
    fall([...nr.m, ...rf.m, ...core.m, ev.d.querySelector('.m')], B2 - 0.42);
    tl.to([a1, a2], { x: -240, opacity: 0, filter: 'blur(12px)', duration: 0.34, ease: 'power2.in' }, B2 - 0.4);
    flip(B2 - 0.12, false);

    /* ---------------- integrate ---------------- */
    const ci = line(root, 'continuous integration', 440, 160);
    carryIn(ci.m, B2 - 0.05);
    fall(ci.m, word('integrate', 'code') - 0.2);
    // header above the terminal: "every check in", then a token cycle on "test"
    const hdr = line(root, 'every check in', 130, 100);
    riseAt(hdr, [word('integrate', 'each'), word('integrate', 'check'), word('integrate', 'in', 2)]);
    sink(hdr.w, sent('integrate', 3) - 0.3);
    const tfix = line(root, 'test', 130, 100, { align: 'right', x: 700 });
    rise(tfix.w, word('integrate', 'test'));
    const tslots = [['automation', word('integrate', 'automation')], ['driven development', word('integrate', 'driven')], ['suites', word('integrate', 'suites')]];
    const TS = tslots.map(([t]) => line(root, t, 130, 100, { align: 'left', x: 740, color: 'var(--accent)' }));
    TS.forEach((L, i) => { rise(L.w, tslots[i][1], 0.45); if (i < 2) sink(L.w, tslots[i + 1][1] - 0.28); });

    const term = el(root, 'div', 'term');
    term.innerHTML = '<div class="bar"><i></i><i></i><i></i><span style="margin-left:16px">every check in</span></div>';
    tl.fromTo(term, { opacity: 0, scale: 0.94 }, { opacity: 1, scale: 1, duration: 0.5, ease: 'power3.out' }, word('integrate', 'code'));
    const tline = (tokens, color) => {
      const d = el(term, 'div', 'tl'); if (color) d.style.color = color;
      return tokens.map(([t, at], i) => { const s = el(d, 'span', 'tk', t); if (i < tokens.length - 1) d.appendChild(document.createTextNode(' ')); tl.fromTo(s, { opacity: 0, y: 14 }, { opacity: 1, y: 0, duration: 0.14, ease: 'power2.out' }, at); return s; });
    };
    tline([['$', word('integrate', 'checked')], ['git', word('integrate', 'checked') + 0.12], ['push', word('integrate', 'in', 1)]]);
    tline([['running', word('integrate', 'triggers')], ['quick', word('integrate', 'quick')], ['tests', word('integrate', 'tests')]], '#9aa0a6');
    const l3 = el(term, 'div', 'tl');
    const hl = el(l3, 'span', 'hl'); const sw = el(hl, 'span', 'sw');
    const reg = [['regression', word('integrate', 'regressions')], ['found:', word('integrate', 'regressions') + 0.25]].map(([t, at], i) => {
      const s = el(hl, 'span', 'tk', t); if (!i) hl.appendChild(document.createTextNode(' '));
      tl.fromTo(s, { opacity: 0, y: 14 }, { opacity: 1, y: 0, duration: 0.14, ease: 'power2.out' }, at); return s;
    });
    tl.fromTo(sw, { scaleX: 0 }, { scaleX: 1, duration: 0.45, ease: 'power2.inOut' }, word('integrate', 'regressions') + 0.35);
    tl.to(reg, { color: '#202124', duration: 0.2 }, word('integrate', 'regressions') + 0.5);
    l3.appendChild(document.createTextNode(' '));
    [['fix', word('integrate', 'fix')], ['it', word('integrate', 'fix') + 0.15], ['now', word('integrate', 'immediately')]].forEach(([t, at], i) => {
      const s = el(l3, 'span', 'tk', t); if (i < 2) l3.appendChild(document.createTextNode(' '));
      tl.fromTo(s, { opacity: 0, y: 14 }, { opacity: 1, y: 0, duration: 0.14, ease: 'power2.out' }, at);
    });
    const l4 = tline([['feedback', word('integrate', 'feedback')], ['in', word('integrate', 'in', 4)], ['under', word('integrate', 'less')], ['10', word('integrate', 'ten')], ['minutes', word('integrate', 'minutes')]]);
    tl.to([l4[3], l4[4]], { color: '#f0e15a', duration: 0.25 }, word('integrate', 'minutes') + 0.2);
    return tl;
  },
});

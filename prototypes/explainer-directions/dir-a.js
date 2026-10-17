// Direction A, Infinite Canvas: the whole video is one map; the camera flies between its tiles.
DIRECTIONS.push({
  key: 'A', name: 'Infinite Canvas', tagline: 'One map, a camera that flies between its parts, no cuts',
  summary: 'Every scene is a tile on one large map of the video. The camera holds still while a scene builds, pushes in on the cue, and carries itself to the next tile instead of cutting. The hook ends on the whole map, and so does the last scene.',
  axes: {
    camera: 'A 2D camera over one 6240 by 3720 canvas. It moves only on a spoken cue (push in, truck, pull back) with power3.inOut over 1.2 to 2.2 s, and never drifts while a scene holds.',
    seams: 'No cuts. The camera carries to the next tile, with 6 px of motion blur at peak speed. The hook and the last scene pull back to the whole map.',
    type: 'Steady. Labels are pills attached to the object they name, and they fade and rise by whole words.',
    texture: 'Flat ground, one tint of the profile per tile (white, a pale accent, a pale chip yellow), a faint dashed path joining the tiles in video order.',
    threeD: 'None.',
  },
  refs: [
    { label: 'Kurzgesagt, pathway map', url: 'https://youtu.be/BSypUV6QUNw?t=155', what: 'a map built row by row, zoom into one row' },
    { label: 'ByteByteGo, URL to page', url: 'https://youtu.be/AlkDbnbv7dk?t=230', what: 'zoom into a sub-diagram' },
    { label: '3Blue1Brown, magnifier', url: 'https://youtu.be/LPZh9BOjkQs?t=122', what: 'zoom-callout inset joined by two lines' },
  ],
  rtl: 'Mirror the map: tiles run right to left, the camera path and every arrow flip. Pills and terminal lines grow by whole words. Zoom moves are direction-neutral.',
  composer: 'New: a wrapper camera over one canvas that spans scenes, so scene files share one world and each scene names its tile and camera beats. Seams become camera moves on the root timeline. Pure CSS transforms, so determinism holds; a large canvas costs paint time per frame.',
  scenes: {
    hook: 'Opens tight on two delivery lanes, fast and safe against slow and breaking. Pulls back to the title on "DORA\'s research", pushes into a correlation plot on "correlated", then pulls out to the whole map of the video on "piece by piece".',
    trails: 'The camera trucks station to station along one track: research cards stream past, a finding repeats, Core settles as a solid block. "Your practices" spins on "churn". A pull back shows fast dots before Core and slow dots after it.',
    integrate: 'A check-in loop, with a zoom-callout from the tests node to an enlarged terminal. The regression node flashes red, then green. A "< 10 min" arc closes the loop, and the camera pulls out to the whole map again.',
  },
  css: `
.dir-a .cam { position: absolute; left: 0; top: 0; transform-origin: 0 0; will-change: transform; }
.dir-a .tile { position: absolute; width: 1920px; height: 1080px; border-radius: 28px; }
.dir-a .tile .ttl { position: absolute; left: 80px; top: 64px; font: 600 54px var(--ft); color: var(--faint); opacity: .55; }
.dir-a .tile.ghost { background: #f4f4f5; }
.dir-a .tile.ghost .ttl { left: 50%; top: 50%; transform: translate(-50%, -50%); font-size: 92px; white-space: nowrap; color: var(--rule); opacity: 1; }
.dir-a .path { position: absolute; left: 0; top: 0; overflow: visible; }
.dir-a .pill { position: absolute; padding: 10px 26px; border-radius: 999px; background: var(--text); color: #fff; font: 600 34px var(--ft); white-space: nowrap; }
.dir-a .pill.acc { background: var(--accent); }
.dir-a .pill.stop { background: var(--stop); }
.dir-a .pill.ok { background: var(--ok); }
.dir-a .pill.chip { background: var(--chip); color: var(--text); }
.dir-a .kick { position: absolute; font: 600 40px var(--ft); color: var(--accent); }
.dir-a .title { position: absolute; font: 600 96px/1.05 var(--ft); letter-spacing: -0.01em; width: 1700px; }
.dir-a .title .w { display: inline-block; position: relative; }
.dir-a .hl { position: absolute; left: -8px; right: -8px; bottom: 6px; height: 34px; background: var(--chip); z-index: -1; transform-origin: 0 50%; }
.dir-a .lane { position: absolute; height: 6px; background: var(--line); border-radius: 3px; }
.dir-a .dot { position: absolute; width: 34px; height: 34px; border-radius: 50%; background: var(--accent); margin: -14px 0 0 -17px; }
.dir-a .lbl { position: absolute; font: 400 30px var(--ft); color: var(--muted); white-space: nowrap; }
.dir-a .axis { position: absolute; background: var(--rule); }
.dir-a .pt { position: absolute; width: 22px; height: 22px; margin: -11px 0 0 -11px; border-radius: 50%; background: var(--rule); }
.dir-a .station { position: absolute; width: 300px; height: 300px; margin: -150px 0 0 -150px; border-radius: 40px; background: #fff; border: 4px solid var(--line); }
.dir-a .paper { position: absolute; width: 70px; height: 92px; border-radius: 10px; background: #fff; border: 3px solid var(--accent); }
.dir-a .core { background: var(--ok); border-color: var(--ok); }
.dir-a .node { position: absolute; width: 260px; height: 130px; margin: -65px 0 0 -130px; border-radius: 30px; background: #fff; border: 4px solid var(--text); display: grid; place-items: center; font: 600 38px var(--ft); }
.dir-a .term { position: absolute; background: #202124; border-radius: 26px; color: #e8eaed; font: 400 38px/1.75 var(--fm); padding: 92px 48px 40px; overflow: hidden; }
.dir-a .term .bar { position: absolute; left: 0; right: 0; top: 0; height: 64px; background: #2d2e31; display: flex; align-items: center; gap: 12px; padding: 0 26px; font-size: 26px; color: #9aa0a6; }
.dir-a .term .bar i { width: 16px; height: 16px; border-radius: 50%; background: #5f6368; display: block; }
.dir-a .term .ln { white-space: nowrap; }
.dir-a .term .ln .w { opacity: 0; }
.dir-a .box { position: absolute; border: 4px solid var(--accent); border-radius: 22px; }
`,
  build(frame) {
    const { el, sent, word, S } = H;
    const tl = gsap.timeline({ paused: true });
    const TW = 1920, TH = 1080, GX = 2160, GY = 1320;
    const cam = el(frame, 'div', 'cam');
    const svgIn = parent => { const v = document.createElementNS('http://www.w3.org/2000/svg', 'svg'); v.setAttribute('class', 'path'); parent.appendChild(v); return v; };
    const mid = 'ah' + (DIRECTIONS.aSeq = (DIRECTIONS.aSeq || 0) + 1);
    // tiles in video order, a snake over a 3 by 3 grid; the three built scenes are hook, trails, integrate
    const tiles = [
      ['hook', 'Fast and stable', 0, 0, '#ffffff'], ['context', 'What DORA Core is', 1, 0], ['trails', 'Why Core moves slowly', 2, 0, '#eaf3fb'],
      ['integrate', 'Integration and tests', 2, 1, '#fdf9de'], ['predicts', 'Delivery performance', 1, 1], ['tradeoff', 'Speed and stability', 0, 1],
      ['wellbeing', 'Well-being', 0, 2], ['loop', 'The improvement loop', 1, 2], ['end', 'Keep improving', 2, 2],
    ];
    const T = {};
    const svg = svgIn(cam);
    svg.setAttribute('width', 3 * GX); svg.setAttribute('height', 3 * GY);
    const pts = tiles.map(([, , c, r]) => [c * GX + TW / 2, r * GY + TH / 2]);
    svg.innerHTML = `<path d="M${pts.map(p => p.join(' ')).join(' L')}" fill="none" stroke="#9a9b9c" stroke-width="10" stroke-dasharray="4 26" stroke-linecap="round"/>`;
    for (const [id, name, c, r, bg] of tiles) {
      const t = el(cam, 'div', 'tile' + (bg ? '' : ' ghost'));
      Object.assign(t.style, { left: c * GX + 'px', top: r * GY + 'px', background: bg || '' });
      if (bg) t.style.boxShadow = '0 0 0 4px #dedddf';
      t._ttl = el(t, 'div', 'ttl', name);
      T[id] = { el: t, x: c * GX, y: r * GY };
    }
    const at = (p, x, y) => Object.assign(p.style, { left: x + 'px', top: y + 'px' });
    // camera: frame world point (x, y) at scale s
    const camAt = (x, y, s) => ({ x: 960 - x * s, y: 540 - y * s, scale: s });
    const fly = (id, x, y, s, t0, d = 1.3, blur = 0) => {
      tl.to(cam, { ...camAt(T[id].x + x, T[id].y + y, s), duration: d, ease: 'power3.inOut' }, t0);
      if (blur) tl.fromTo(cam, { filter: 'blur(0px)' }, { filter: `blur(${blur}px)`, duration: d / 2, ease: 'power2.in', yoyo: true, repeat: 1, immediateRender: false }, t0);
    };
    const overview = () => camAt(1.5 * GX - (GX - TW) / 2, 1.5 * GY - (GY - TH) / 2, 0.275);
    const pop = (e, t0, from = { opacity: 0, y: 24 }) => tl.fromTo(e, from, { opacity: 1, y: 0, x: 0, scale: 1, duration: 0.45, ease: 'power2.out' }, t0);

    /* ---------- hook ---------- */
    const h = T.hook.el; h._ttl.remove();
    const kick = el(h, 'div', 'kick', 'DORA Core'); at(kick, 140, 120);
    const title = el(h, 'div', 'title'); at(title, 140, 180);
    const tw = H.words(title, 'Speed and stability are not tradeoffs');
    for (const i of [0, 2]) { const hl = el(tw[i], 'span', 'hl'); tl.fromTo(hl, { scaleX: 0 }, { scaleX: 1, duration: 0.4, ease: 'power2.out' }, word('hook', i ? 'stability' : 'speed')); }
    const ul = el(h, 'div', 'lane'); at(ul, 140, 395); Object.assign(ul.style, { width: '0px', height: '10px', background: 'var(--stop)' });
    // two delivery lanes
    const lanes = [[540, 'quickly and safely', 'acc', 'quickly'], [760, 'slowly, and still breaking', 'stop', 'slowly']];
    lanes.forEach(([y, label, kind, cue], li) => {
      const lane = el(h, 'div', 'lane'); at(lane, 140, y); lane.style.width = '1040px';
      const p = el(h, 'div', 'pill ' + kind, label); at(p, 140, y + 36);
      pop(p, word('hook', cue));
      const n = li ? 3 : 7, dur = li ? 5.2 : 1.6;
      for (let i = 0; i < n; i++) {
        const d = el(h, 'div', 'dot'); at(d, 140, y + 3);
        if (li) d.style.background = 'var(--muted)';
        const t0 = word('hook', cue) + i * (li ? 1.6 : 0.42);
        tl.fromTo(d, { x: 0, opacity: 0 }, { x: 1040, opacity: 1, duration: dur, ease: 'none', repeat: li ? 1 : 4, immediateRender: false }, t0);
        tl.set(d, { opacity: 0 }, t0 + dur * (li ? 2 : 5));
        tl.set(d, { opacity: 0 }, 0);
        if (li && i === 1) tl.to(d, { background: '#b84b33', scale: 1.5, duration: 0.25 }, word('hook', 'break'));
      }
    });
    tl.set([kick, title], { opacity: 0 }, 0);
    pop(kick, sent('hook', 2) + 0.4); pop(title, sent('hook', 2) + 0.55);
    tl.to(ul, { width: 690, duration: 0.5, ease: 'power2.out' }, word('hook', 'not'));
    // correlation plot
    const ox = 1300, oy = 960, pw = 500, ph = 470;
    const ax = el(h, 'div', 'axis'); at(ax, ox, oy); Object.assign(ax.style, { width: pw + 'px', height: '4px' });
    const ay = el(h, 'div', 'axis'); at(ay, ox, oy - ph); Object.assign(ay.style, { width: '4px', height: ph + 'px' });
    const lx = el(h, 'div', 'lbl', 'speed'); at(lx, ox + pw - 90, oy + 12);
    const ly = el(h, 'div', 'lbl', 'stability'); at(ly, ox + 16, oy - ph - 8);
    const rnd = H.rng(42), P = [];
    for (let i = 0; i < 26; i++) {
      const u = rnd(), v = Math.min(1, Math.max(0, u + (rnd() - 0.5) * 0.28));
      const p = el(h, 'div', 'pt'); at(p, ox + 30 + u * (pw - 60), oy - 30 - v * (ph - 60)); P.push([p, u]);
      tl.fromTo(p, { scale: 0 }, { scale: 1, duration: 0.3, ease: 'back.out(1.6)' }, word('hook', 'correlated') + i * 0.04);
    }
    tl.set([ax, ay, lx, ly], { opacity: 0 }, 0); tl.to([ax, ay, lx, ly], { opacity: 1, duration: 0.4 }, sent('hook', 3));
    tl.to(P.filter(([, u]) => u > 0.68).map(([p]) => p), { background: '#2782cc', scale: 1.35, duration: 0.35 }, word('hook', 'top'));
    tl.to(P.filter(([, u]) => u < 0.32).map(([p]) => p), { background: '#b84b33', scale: 1.35, duration: 0.35 }, word('hook', 'low'));
    const pt = el(h, 'div', 'pill acc', 'Top performers'); at(pt, 1460, 370); pop(pt, word('hook', 'top'));
    const p5 = el(h, 'div', 'pill chip', '5 of 5 metrics'); at(p5, 1470, 440); pop(p5, word('hook', 'five'));
    const pl = el(h, 'div', 'pill stop', 'Low performers'); at(pl, 1340, 990); pop(pl, word('hook', 'low'));

    tl.set(cam, camAt(640, 700, 1.45), 0);
    fly('hook', 960, 540, 1, sent('hook', 2), 1.4);
    fly('hook', 1560, 720, 1.55, sent('hook', 3), 1.2);
    tl.to(cam, { ...overview(), duration: 2.2, ease: 'power3.inOut' }, sent('hook', 5));
    const p0 = svg.querySelector('path'); const len = 9 * GX;
    tl.fromTo(p0, { strokeDashoffset: len }, { strokeDashoffset: 0, duration: 3.6, ease: 'power1.inOut' }, sent('hook', 5) + 0.4);
    tiles.forEach(([id], i) => { if (id !== 'hook') tl.fromTo(T[id].el, { opacity: 0, scale: 0.92 }, { opacity: 1, scale: 1, duration: 0.5, ease: 'power2.out' }, sent('hook', 5) + 0.5 + i * 0.32); });

    /* ---------- trails ---------- */
    const tr = T.trails.el, Y = 640;
    const track = el(tr, 'div', 'lane'); at(track, 300, Y); Object.assign(track.style, { width: '1320px', height: '10px' });
    const st = [[360, 'New research', 'Fast moving', 1], [960, 'Repeated findings', 'Proven over time', 2], [1560, 'DORA Core', 'Evergreen guide', 4]];
    const SN = st.map(([x, label, note, n], i) => {
      const s = el(tr, 'div', 'station' + (i === 2 ? ' core' : '')); at(s, x, Y);
      const pl1 = el(tr, 'div', 'pill' + (i === 2 ? ' ok' : ''), label); at(pl1, x - 150, Y + 190);
      const nt = el(tr, 'div', 'lbl', note); at(nt, x - 150, Y + 262);
      tl.fromTo(s, { scale: 0.6, opacity: 0 }, { scale: 1, opacity: 1, duration: 0.6, ease: 'power3.out' }, sent('trails', n));
      pop(pl1, sent('trails', n) + 0.2); pop(nt, sent('trails', n) + 0.35);
      return s;
    });
    // research papers stream fast through station one
    const rr = H.rng(7);
    for (let i = 0; i < 9; i++) {
      const p = el(tr, 'div', 'paper'); at(p, 120, Y - 46 + (rr() - 0.5) * 120);
      tl.fromTo(p, { x: 0, opacity: 0, rotation: (rr() - 0.5) * 30 }, { x: 480, opacity: 1, duration: 0.9, ease: 'none', immediateRender: false }, sent('trails', 1) + 0.4 + i * 0.35);
      tl.to(p, { opacity: 0, duration: 0.2 }, sent('trails', 1) + 1.1 + i * 0.35);
      tl.set(p, { opacity: 0 }, 0);
    }
    // two findings stack in station two
    for (let i = 0; i < 2; i++) {
      const p = el(tr, 'div', 'paper'); at(p, 925 + i * 18, Y - 66 + i * 18);
      tl.fromTo(p, { opacity: 0, y: -80 }, { opacity: 1, y: 0, duration: 0.5, ease: 'power3.out' }, sent('trails', 2) + 0.5 + i * 0.9);
    }
    const x2 = el(tr, 'div', 'pill chip', 'twice'); at(x2, 1020, Y - 150); pop(x2, sent('trails', 2) + 2.4);
    // practices that churn, then settle on Core
    const pr = el(tr, 'div', 'node', 'Your practices'); at(pr, 660, 260); pr.style.width = '360px'; pr.style.marginLeft = '-180px';
    pop(pr, sent('trails', 3));
    tl.to(pr, { rotation: 1080, duration: 3.4, ease: 'power1.inOut' }, sent('trails', 3) + 0.4);
    const ch = el(tr, 'div', 'pill stop', 'counterproductive churn'); at(ch, 860, 210); pop(ch, word('trails', 'churn'));
    tl.to(ch, { opacity: 0, duration: 0.3 }, sent('trails', 4));
    tl.to(pr, { x: 900, borderColor: '#558141', duration: 1, ease: 'power3.inOut' }, sent('trails', 4) + 0.6);
    // fast dots before Core, slow after it
    for (let i = 0; i < 5; i++) {
      const d = el(tr, 'div', 'dot'); at(d, 360, Y + 5);
      tl.fromTo(d, { x: 0, opacity: 1 }, { x: 600, duration: 0.7, ease: 'none', repeat: 3, immediateRender: false }, sent('trails', 5) + i * 0.28);
      tl.set(d, { opacity: 0 }, 0); tl.set(d, { opacity: 0 }, sent('trails', 5) + i * 0.28 + 2.8);
    }
    const slow = el(tr, 'div', 'dot'); at(slow, 960, Y + 5); slow.style.background = 'var(--ok)';
    tl.fromTo(slow, { x: 0, opacity: 1 }, { x: 600, duration: 4.4, ease: 'none', immediateRender: false }, sent('trails', 5) + 0.3);
    tl.set(slow, { opacity: 0 }, 0);

    fly('trails', 620, Y, 1.35, sent('hook', 5) + 4.3, 1.7, 6);
    fly('trails', 960, Y, 1.5, sent('trails', 2), 1.1);
    fly('trails', 760, 470, 1.2, sent('trails', 3), 1.1);
    fly('trails', 1460, Y - 40, 1.35, sent('trails', 4), 1.2);
    fly('trails', 960, 540, 1, sent('trails', 5), 1.3);

    /* ---------- integrate ---------- */
    const ig = T.integrate.el, I0 = S.integrate.start;
    ig._ttl.style.opacity = 0;
    const nodes = [['Check in', 300, 330], ['Quick tests', 700, 330], ['Fix now', 500, 680]];
    const svg2 = svgIn(ig); svg2.setAttribute('width', 1920); svg2.setAttribute('height', 1080);
    svg2.innerHTML = `<defs><marker id="${mid}" viewBox="0 0 10 10" refX="7" refY="5" markerWidth="5" markerHeight="5" orient="auto"><path d="M0 0 L10 5 L0 10z" fill="#202124"/></marker></defs>
      <path class="e e0" d="M430 330 L560 330" stroke="#202124" stroke-width="6" fill="none" marker-end="url(#${mid})"/>
      <path class="e e1" d="M680 400 Q660 560 590 620" stroke="#202124" stroke-width="6" fill="none" marker-end="url(#${mid})"/>
      <path class="e e2" d="M400 620 Q320 520 300 410" stroke="#202124" stroke-width="6" fill="none" marker-end="url(#${mid})"/>
      <path class="arc" d="M500 120 A 380 380 0 1 1 499 120" stroke="#558141" stroke-width="10" fill="none" stroke-dasharray="2400" stroke-dashoffset="2400"/>
      <path class="lead" d="M840 260 L1040 180 M840 400 L1040 860" stroke="#2782cc" stroke-width="4" fill="none" stroke-dasharray="900" stroke-dashoffset="900"/>`;
    const N = nodes.map(([label, x, y]) => { const n = el(ig, 'div', 'node', label); at(n, x, y); return n; });
    pop(N[0], sent('integrate', 1)); pop(N[1], word('integrate', 'triggers'));
    tl.fromTo(svg2.querySelector('.e0'), { opacity: 0 }, { opacity: 1, duration: 0.3 }, word('integrate', 'triggers'));
    const box = el(ig, 'div', 'box'); at(box, 560, 255); Object.assign(box.style, { width: '280px', height: '150px' });
    const term = el(ig, 'div', 'term'); at(term, 1040, 180); Object.assign(term.style, { width: '780px', height: '680px' });
    term.innerHTML = '<div class="bar"><i></i><i></i><i></i><span style="margin-left:14px">every check in</span></div>';
    tl.fromTo(box, { opacity: 0, scale: 1.3 }, { opacity: 1, scale: 1, duration: 0.4, ease: 'power2.out' }, word('integrate', 'quick') + 0.3);
    tl.to(svg2.querySelector('.lead'), { strokeDashoffset: 0, duration: 0.6, ease: 'power2.inOut' }, word('integrate', 'quick') + 0.5);
    tl.fromTo(term, { opacity: 0, scale: 0.2, transformOrigin: '0% 15%' }, { opacity: 1, scale: 1, duration: 0.7, ease: 'power3.out' }, word('integrate', 'quick') + 0.8);
    const lines = [['$ git push', word('integrate', 'quick') + 1.4, '#e8eaed'], ['running quick tests', word('integrate', 'quick') + 2.1, '#9aa0a6'],
      ['regression found: fix it now', sent('integrate', 2), '#f28b82'], ['feedback in under 10 minutes', sent('integrate', 4) + 0.5, '#81c995']];
    for (const [text, t0, c] of lines) {
      const ln = el(term, 'div', 'ln'); ln.style.color = c;
      H.words(ln, text).forEach((w, i) => tl.fromTo(w, { opacity: 0 }, { opacity: 1, duration: 0.05 }, t0 + i * 0.12));
    }
    tl.fromTo(svg2.querySelector('.e1'), { opacity: 0 }, { opacity: 1, duration: 0.3 }, word('integrate', 'regressions'));
    pop(N[2], word('integrate', 'regressions'));
    tl.to(N[2], { borderColor: '#b84b33', color: '#b84b33', duration: 0.2 }, word('integrate', 'regressions'));
    tl.to(N[2], { borderColor: '#558141', color: '#558141', duration: 0.3 }, word('integrate', 'immediately'));
    tl.fromTo(svg2.querySelector('.e2'), { opacity: 0 }, { opacity: 1, duration: 0.3 }, word('integrate', 'immediately'));
    const tdd = el(ig, 'div', 'pill acc', 'test first'); at(tdd, 580, 160); pop(tdd, word('integrate', 'test'));
    tl.to(svg2.querySelector('.arc'), { strokeDashoffset: 0, duration: 1.4, ease: 'power2.inOut' }, word('integrate', 'ten') - 0.6);
    const ten = el(ig, 'div', 'pill ok', '< 10 min'); at(ten, 380, 880); pop(ten, word('integrate', 'ten'));

    fly('integrate', 760, 500, 1.3, I0 - 0.7, 1.5, 6);
    fly('integrate', 960, 540, 1, word('integrate', 'quick'), 1.2);
    tl.to(cam, { ...overview(), duration: 1.8, ease: 'power3.inOut' }, sent('integrate', 4) + 4.2);
    return tl;
  },
});

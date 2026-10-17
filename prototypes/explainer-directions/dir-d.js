// Direction D, Depth Stack: one lit 3D world under HTML labels; the camera dollies from object to object.
DIRECTIONS.push({
  key: 'D', name: 'Depth Stack', tagline: 'Lit 3D objects, a dolly camera, labels in HTML',
  summary: 'Each idea is a solid object in one lit 3D world: metric bars, an exploded stack, a check-in conveyor. The camera dollies from one object to the next instead of cutting, and every word on screen is HTML pinned to a 3D point, so Arabic shapes as it does on a page.',
  axes: {
    camera: 'A Three.js perspective camera (35 degree lens) on one clock. It dollies and cranes on the spoken cue with power3.inOut over 1.4 to 2.4 s, and holds still while a scene builds.',
    seams: 'Dolly continuity: the camera flies from one scene\'s object to the next across the boundary, so nothing cuts. The last scene pulls back to show all three objects.',
    type: 'HTML over the canvas. Pills and notes are pinned to 3D anchors and rise by whole words. The terminal is an HTML plane tilted in CSS 3D.',
    texture: 'An opaque white ground with a soft floor shadow. Matte lit solids in the profile colours. No grain.',
    threeD: 'Yes: live Three.js (r159) rendered from the timeline time, never from a clock. Low poly, about 30 boxes.',
  },
  refs: [
    { label: 'AMD, exploded chip', url: 'https://youtu.be/ymfEB4MwrO0?t=52', what: 'layers separate on a slow dolly' },
    { label: 'Applied Materials, stack', url: 'https://youtu.be/-egYoxajTz0?t=13', what: 'lit layers built one by one' },
    { label: 'HyperFrames, 3D cards', url: 'https://static.heygen.ai/hyperframes-oss/docs/images/prompting/example-3d-cards.mp4', what: 'Three.js inside a composition' },
    { label: 'Linear, tilted UI', url: 'https://youtu.be/mRql2VJ99gM?t=9', what: 'a UI plane at rotateX 35, rotateZ -12' },
  ],
  rtl: 'Labels are HTML pinned to 3D points, so Arabic joins as on a page. Mirror the world on x (bar order, conveyor direction, the tilt of the terminal plane). The terminal grows by whole words.',
  composer: 'New: a Three.js layer driven by the HyperFrames adapter, render(t) from the seek time, plus a label layer that projects 3D anchors into HTML. Open for the 3D path ticket: GPU frames are not proven pixel-stable (only SwiftShader is), so the gate needs SwiftShader live, GPU with one worker, or a cached clip insert rendered once.',
  scenes: {
    hook: 'Ten flat tiles on a floor. The title lands on "DORA\'s research". On "correlated" both rows rise together. Top performers grow tall in blue across all five metrics, and low performers sink red. On "piece by piece" the camera cranes up and over the bars toward the stack behind them.',
    trails: 'An exploded stack. New research drops in on top with papers sliding fast across it, then Repeated findings, then DORA Core as the green base. The top layer spins on "churn" while Core holds still. On the last line the layers close into one block.',
    integrate: 'The camera dollies to a check-in conveyor in front of the stack. Each check-in cube runs through the tests gate. One cube stops red on "regressions" and turns green on "immediately". A terminal tilts in beside it, then the camera pulls back to all three objects.',
  },
  css: `
.dir-d canvas { position: absolute; inset: 0; width: 100%; height: 100%; display: block; }
.dir-d .lay { position: absolute; inset: 0; pointer-events: none; }
.dir-d .anc { position: absolute; left: 0; top: 0; width: 0; height: 0; }
.dir-d .anc > * { position: absolute; white-space: nowrap; }
.dir-d .pill { padding: 10px 24px; border-radius: 999px; background: var(--text); color: #fff; font: 600 32px var(--ft); transform: translate(-50%, -100%); }
.dir-d .pill.acc { background: var(--accent); }
.dir-d .pill.ok { background: var(--ok); }
.dir-d .pill.stop { background: var(--stop); }
.dir-d .pill.chip { background: var(--chip); color: var(--text); }
.dir-d .note { font: 400 28px var(--ft); color: var(--muted); transform: translate(-50%, 8px); }
.dir-d .metric { font: 400 30px/1.15 var(--ft); color: var(--muted); white-space: normal; width: 260px; text-align: center; transform: translate(-50%, 10px); }
.dir-d .kick { position: absolute; left: 120px; top: 92px; font: 600 38px var(--ft); color: var(--accent); }
.dir-d .title { position: absolute; left: 120px; top: 144px; width: 1500px; font: 600 84px/1.05 var(--ft); letter-spacing: -0.01em; color: var(--text); }
.dir-d .title .w { display: inline-block; }
.dir-d .tilt { position: absolute; left: 1060px; top: 90px; width: 780px; height: 520px; perspective: 1800px; }
.dir-d .plane { position: absolute; inset: 0; transform-origin: 50% 70%; transform-style: preserve-3d; }
.dir-d .term { position: absolute; inset: 0; background: #202124; border-radius: 26px; color: #e8eaed; font: 400 40px/1.75 var(--fm); padding: 96px 52px 40px; overflow: hidden; box-shadow: 0 50px 90px #20212455;
  -webkit-mask-image: linear-gradient(to bottom, #000c 0%, #000 30%); mask-image: linear-gradient(to bottom, #000c 0%, #000 30%); }
.dir-d .term .bar { position: absolute; left: 0; right: 0; top: 0; height: 66px; background: #2d2e31; display: flex; align-items: center; gap: 12px; padding: 0 26px; font-size: 26px; color: #9aa0a6; }
.dir-d .term .bar i { width: 16px; height: 16px; border-radius: 50%; background: #5f6368; display: block; }
.dir-d .term .ln { white-space: nowrap; }
`,
  build(frame) {
    const { el, sent, word, S } = H;
    const tl = gsap.timeline({ paused: true });
    const W = 1920, HH = 1080;

    // renderer and world
    const canvas = el(frame, 'canvas');
    const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, preserveDrawingBuffer: true, alpha: false });
    renderer.setPixelRatio(1); renderer.setSize(W, HH, false); renderer.setClearColor(0xffffff, 1);
    renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(35, W / HH, 0.1, 200);
    scene.add(new THREE.HemisphereLight(0xffffff, 0xc9cbd1, 1.6));
    const sun = new THREE.DirectionalLight(0xffffff, 2.2);
    sun.position.set(-8, 16, 10); sun.castShadow = true; sun.shadow.mapSize.set(1024, 1024);
    Object.assign(sun.shadow.camera, { left: -16, right: 16, top: 16, bottom: -16, near: 1, far: 60 });
    sun.target.position.set(-2, 0, -9); scene.add(sun, sun.target);
    const floor = new THREE.Mesh(new THREE.PlaneGeometry(120, 120), new THREE.ShadowMaterial({ opacity: 0.12 }));
    floor.rotation.x = -Math.PI / 2; floor.receiveShadow = true; scene.add(floor);
    const geo = new THREE.BoxGeometry(1, 1, 1);
    const C = { grey: new THREE.Color('#dedddf'), acc: new THREE.Color('#2782cc'), ok: new THREE.Color('#558141'), stop: new THREE.Color('#b84b33'), ink: new THREE.Color('#202124'), chip: new THREE.Color('#f0e15a') };
    const box = (sx, sy, sz, col, opts = {}) => {
      const m = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ color: col.clone(), roughness: 0.62, metalness: 0.02, transparent: !!opts.fade }));
      m.scale.set(sx, sy, sz); m.castShadow = true; m.receiveShadow = true; scene.add(m); return m;
    };

    // camera proxy: position and look target, tweened on the timeline
    const cam = { x: 0, y: 9.5, z: 12, tx: 0, ty: 0.6, tz: 0 };
    const dolly = (to, t0, d = 1.6, ease = 'power3.inOut') => tl.to(cam, { ...to, duration: d, ease }, t0);

    // HTML labels pinned to 3D points
    const lay = el(frame, 'div', 'lay');
    const pins = [];
    const pin = (fn, cls, html) => { const a = el(lay, 'div', 'anc'); const p = el(a, 'div', cls, html); pins.push([a, fn]); return p; };
    const show = (e, t0) => tl.fromTo(e, { opacity: 0, y: 18 }, { opacity: 1, y: 0, duration: 0.45, ease: 'power2.out' }, t0);
    const hide = (e, t0) => tl.to(e, { opacity: 0, duration: 0.3 }, t0);

    /* ---------- hook: ten tiles become metric bars ---------- */
    const metrics = ['deployment frequency', 'change lead time', 'change fail rate', 'failed deployment recovery time', 'rework rate'];
    const rows = [0, 1].map(r => metrics.map((m, i) => {
      const p = { h: 0.08, k: 0, a: 0 };
      const mesh = box(1.3, 1, 1.3, C.grey, { fade: true });
      mesh.position.set((i - 2) * 1.9, 0, r ? 1.25 : -1.25);
      return { p, mesh, r, i };
    }));
    const bars = rows.flat();
    bars.forEach(({ p }, j) => tl.to(p, { a: 1, duration: 0.5, ease: 'power2.out' }, 0.35 + j * 0.12));
    tl.to(rows[0].map(b => b.p).concat(rows[1].map(b => b.p)), { h: 1.1, duration: 0.9, ease: 'power3.inOut', stagger: 0.05 }, word('hook', 'correlated'));
    const tops = [3.1, 2.7, 3.3, 2.9, 3.0], lows = [0.42, 0.55, 0.36, 0.5, 0.44];
    rows[0].forEach(({ p }, i) => tl.to(p, { h: tops[i], k: 1, duration: 1.1, ease: 'power3.out' }, word('hook', 'top') + i * 0.12));
    rows[1].forEach(({ p }, i) => tl.to(p, { h: lows[i], k: 1, duration: 0.9, ease: 'power3.out' }, word('hook', 'low') + i * 0.1));
    metrics.forEach((m, i) => show(pin(() => [(i - 2) * 1.9, 0, 2.3], 'metric', m), word('hook', 'five') + i * 0.1));
    show(pin(() => [5.6, rows[0][4].p.h + 0.2, -1.25], 'pill acc', 'Top performers'), word('hook', 'top'));
    show(pin(() => [5.6, rows[1][4].p.h + 0.2, 1.25], 'pill stop', 'Low performers'), word('hook', 'low'));
    const kick = el(frame, 'div', 'kick', 'DORA Core');
    const title = el(frame, 'div', 'title');
    const tw = H.words(title, 'Speed and stability are not tradeoffs');
    show(kick, sent('hook', 2));
    tw.forEach((w, i) => show(w, sent('hook', 2) + 0.15 + i * 0.09));
    tl.to(tw[0], { color: '#2782cc', duration: 0.3 }, word('hook', 'speed'));
    tl.to(tw[2], { color: '#2782cc', duration: 0.3 }, word('hook', 'stability'));
    hide([kick, title], sent('hook', 5) + 0.3);

    tl.set(cam, { x: 0, y: 11, z: 11, tx: 0, ty: 0, tz: 0 }, 0);
    dolly({ x: 0, y: 6.5, z: 13.5, tx: 0, ty: 0.4, tz: -0.6 }, sent('hook', 2), 2);
    dolly({ x: 1.5, y: 8.4, z: 13.5, tx: 0.6, ty: 2.0, tz: 0 }, word('hook', 'top') - 0.4, 1.5);
    dolly({ x: 0, y: 10.5, z: 4, tx: 0, ty: 0.5, tz: -10 }, sent('hook', 5) + 0.4, 2.4);

    /* ---------- trails: exploded stack ---------- */
    const SZ = -16;
    const stack = { g: 1.7 };
    const layers = [['New research', 'Fast moving', 1, C.acc], ['Repeated findings', 'Proven over time', 2, C.grey], ['DORA Core', 'Evergreen guide', 4, C.ok]].map(([label, note, n, col], i) => {
      const p = { a: 0, drop: 2.5, rot: 0 };
      const mesh = box(6, 0.32, 3.6, col, { fade: true });
      const L = { p, mesh, lvl: 2 - i };
      tl.to(p, { a: 0.16, drop: 0, duration: 1.2, ease: 'power2.out' }, sent('hook', 5) + 1.4 + i * 0.25);
      tl.fromTo(p, { a: 0.16, drop: 1.2 }, { a: 1, drop: 0, duration: 0.9, ease: 'power3.out', immediateRender: false }, sent('trails', n));
      const yOf = () => L.lvl * stack.g + 0.16 + p.drop;
      const lp = pin(() => [3.4, yOf() + 0.25, SZ + 1.6], 'pill' + (i === 2 ? ' ok' : i === 0 ? ' acc' : ''), label);
      const ln = pin(() => [3.4, yOf() + 0.25, SZ + 1.6], 'note', note);
      show(lp, sent('trails', n) + 0.3); show(ln, sent('trails', n) + 0.45);
      if (i < 2) hide([lp, ln], sent('trails', 5) + 0.3);
      L.y = yOf; return L;
    });
    // papers slide fast across the research layer
    const rr = H.rng(11);
    const papers = Array.from({ length: 6 }, (_, i) => {
      const p = { x: -2.6, a: 0 };
      const mesh = box(0.55, 0.06, 0.75, new THREE.Color('#ffffff'), { fade: true });
      const z = SZ + (rr() - 0.5) * 2.4;
      const t0 = sent('trails', 1) + 0.6 + i * 0.32;
      tl.fromTo(p, { x: -2.6 }, { x: 2.6, duration: 1.1, ease: 'none', repeat: 6, immediateRender: false }, t0);
      tl.to(p, { a: 1, duration: 0.2 }, t0); tl.to(p, { a: 0, duration: 0.3 }, sent('trails', 4));
      return { p, mesh, z };
    });
    tl.to(layers[0].p, { rot: Math.PI * 4, duration: 3.6, ease: 'power1.inOut' }, sent('trails', 3) + 0.3);
    const churn = pin(() => [-3.6, layers[0].y() + 0.9, SZ], 'pill stop', 'counterproductive churn');
    show(churn, word('trails', 'churn')); hide(churn, sent('trails', 4) + 0.2);
    tl.to(stack, { g: 0.36, duration: 1.6, ease: 'power3.inOut' }, sent('trails', 5) + 0.5);
    const slow = pin(() => [-3.4, 0.6, SZ + 1.8], 'pill chip', 'informed by research, slower');
    show(slow, sent('trails', 5) + 1.0);

    dolly({ x: 5.5, y: 7.4, z: SZ + 8.5, tx: 0, ty: 3.2, tz: SZ }, S.trails.start - 1.6, 1.9);
    dolly({ x: 6.2, y: 4.6, z: SZ + 9.2, tx: 0, ty: 1.7, tz: SZ }, sent('trails', 2), 1.5);
    dolly({ x: -2.5, y: 7.2, z: SZ + 9.5, tx: -0.8, ty: 2.6, tz: SZ }, sent('trails', 3), 1.5);
    dolly({ x: 6.4, y: 3.6, z: SZ + 10.4, tx: 0, ty: 1.0, tz: SZ }, sent('trails', 4), 1.6);
    dolly({ x: 9, y: 6.4, z: SZ + 12, tx: 0, ty: 1.2, tz: SZ }, sent('trails', 5), 1.8);

    /* ---------- integrate: check-in conveyor, tilted terminal ---------- */
    const CZ = -9, GX = -6.2;
    const track = box(12, 0.12, 1.1, C.grey, { fade: true }); track.position.set(-7.5, 0.06, CZ);
    const tp = { a: 0 };
    tl.to(tp, { a: 1, duration: 0.8 }, S.integrate.start - 0.8);
    const postA = box(0.25, 2.1, 0.25, C.acc), postB = box(0.25, 2.1, 0.25, C.acc), beam = box(0.25, 0.25, 1.6, C.acc);
    postA.position.set(GX, 1.05, CZ - 0.8); postB.position.set(GX, 1.05, CZ + 0.8); beam.position.set(GX, 2.1, CZ);
    const gate = [postA, postB, beam];
    gate.forEach(m => { m.material.transparent = true; m.material.opacity = 0; });
    const gp = { a: 0, k: 0 };
    tl.to(gp, { a: 1, duration: 0.5 }, word('integrate', 'triggers'));
    tl.to(gp, { k: 1, duration: 0.5 }, word('integrate', 'test'));
    const cubes = Array.from({ length: 5 }, (_, i) => {
      const p = { x: -13, a: 0, k: 0 };
      const mesh = box(0.62, 0.62, 0.62, C.ink, { fade: true });
      const t0 = word('integrate', 'checked') + i * 1.15;
      tl.to(p, { a: 1, duration: 0.3 }, t0);
      if (i === 2) {
        tl.to(p, { x: GX - 0.7, duration: 1.6, ease: 'power2.out' }, t0);
        tl.to(p, { k: 1, duration: 0.25 }, word('integrate', 'regressions'));
        tl.to(p, { k: 2, duration: 0.3 }, word('integrate', 'immediately'));
        tl.to(p, { x: -3.8, duration: 1.4, ease: 'power2.inOut' }, word('integrate', 'immediately') + 0.3);
      } else tl.to(p, { x: -2.0 - i * 0.9, duration: 2.4, ease: 'power2.inOut' }, i < 2 ? t0 : Math.max(t0, word('integrate', 'immediately') + 0.6 + (i - 3) * 0.6));
      return { p, mesh };
    });
    const ipills = [];
    const ipin = (fn, cls, html, t0) => { const e = pin(fn, cls, html); show(e, t0); ipills.push(e); return e; };
    ipin(() => [GX, 2.5, CZ], 'pill acc', 'quick tests', word('integrate', 'quick'));
    const reg = pin(() => [GX - 0.7, 1.15, CZ + 0.6], 'pill stop', 'regression');
    show(reg, word('integrate', 'regressions')); hide(reg, word('integrate', 'immediately') + 0.2);
    ipin(() => [GX, 3.35, CZ], 'pill ok', 'test first', word('integrate', 'test'));
    ipin(() => [GX - 2.4, 2.2, CZ], 'pill chip', 'under 10 min', word('integrate', 'ten'));
    hide(ipills, sent('integrate', 4) + 4.0); hide(slow, S.integrate.start + 0.4);

    const tilt = el(frame, 'div', 'tilt'), plane = el(tilt, 'div', 'plane'), term = el(plane, 'div', 'term');
    term.innerHTML = '<div class="bar"><i></i><i></i><i></i><span style="margin-left:14px">every check in</span></div>';
    tl.fromTo(plane, { opacity: 0, rotationX: 62, rotationZ: -18, y: 260, z: -300 }, { opacity: 1, rotationX: 34, rotationZ: -11, y: 0, z: 0, duration: 1.4, ease: 'power3.out' }, word('integrate', 'quick') - 0.2);
    tl.to(plane, { opacity: 0, y: 200, rotationX: 50, duration: 1.0, ease: 'power2.in' }, sent('integrate', 4) + 4.4);
    const lines = [['$ git push', word('integrate', 'quick') + 0.9, '#e8eaed'], ['running quick tests', word('integrate', 'quick') + 1.5, '#9aa0a6'],
      ['regression found: fix it now', word('integrate', 'regressions'), '#f28b82'], ['feedback in under 10 minutes', word('integrate', 'ten') + 0.2, '#81c995']];
    for (const [text, t0, c] of lines) {
      const ln = el(term, 'div', 'ln'); ln.style.color = c;
      H.words(ln, text).forEach((w, i) => tl.fromTo(w, { opacity: 0 }, { opacity: 1, duration: 0.05 }, t0 + i * 0.12));
    }
    dolly({ x: -13, y: 8, z: CZ + 9, tx: -3.2, ty: 1.6, tz: CZ - 2.2 }, S.integrate.start - 0.9, 2.2);
    dolly({ x: 4, y: 15, z: 14, tx: -3, ty: 0, tz: -7.5 }, sent('integrate', 4) + 4.2, 2.2);

    /* ---------- render from the proxies, once per seek ---------- */
    const v = new THREE.Vector3(), tmp = new THREE.Color();
    tl.renderAt = () => {
      for (const { p, mesh, r } of bars) {
        mesh.scale.y = p.h; mesh.position.y = p.h / 2;
        mesh.material.color.copy(C.grey).lerp(r ? C.stop : C.acc, p.k);
        mesh.material.opacity = p.a; mesh.visible = p.a > 0.01;
      }
      for (const L of layers) {
        L.mesh.position.set(0, L.y(), SZ); L.mesh.rotation.y = L.p.rot;
        L.mesh.material.opacity = L.p.a; L.mesh.visible = L.p.a > 0.01;
      }
      for (const { p, mesh, z } of papers) {
        mesh.position.set(p.x, layers[0].y() + 0.2, z); mesh.rotation.y = layers[0].p.rot;
        mesh.material.opacity = p.a * layers[0].p.a; mesh.visible = mesh.material.opacity > 0.01;
      }
      track.material.opacity = tp.a; track.visible = tp.a > 0.01;
      gate.forEach(m => { m.material.opacity = gp.a; m.visible = gp.a > 0.01; m.material.color.copy(C.acc).lerp(C.ok, gp.k); });
      for (const { p, mesh } of cubes) {
        mesh.position.set(p.x, 0.43, CZ); mesh.material.opacity = p.a; mesh.visible = p.a > 0.01;
        if (p.k <= 1) tmp.copy(C.ink).lerp(C.stop, p.k); else tmp.copy(C.stop).lerp(C.ok, p.k - 1);
        mesh.material.color.copy(tmp);
      }
      camera.position.set(cam.x, cam.y, cam.z); camera.lookAt(cam.tx, cam.ty, cam.tz); camera.updateMatrixWorld();
      for (const [a, fn] of pins) {
        v.set(...fn()).project(camera);
        a.style.transform = `translate(${(v.x + 1) / 2 * W}px, ${(1 - v.y) / 2 * HH}px)`;
        a.style.visibility = v.z < 1 ? 'visible' : 'hidden';
      }
      renderer.render(scene, camera);
    };
    tl.dispose = () => { renderer.dispose(); renderer.forceContextLoss(); geo.dispose(); };
    return tl;
  },
});

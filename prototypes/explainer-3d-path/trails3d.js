// PROTOTYPE: the dora-core "trails" scene as a 3D exploded stack.
// One closed-form world, every state a function of the scene timeline time.
// Trails3D(host, { canvas, pins, code }) returns the paused GSAP timeline:
//   canvas: draw the WebGL layer (false in the clip-insert scene, whose video
//           already holds it)
//   pins:   the HTML labels, projected from 3D points by the same camera math
//   code:   a 12-bit frame-number strip in the canvas corner, read back to
//           prove which clip frame landed on which video frame
window.Trails3D = function (host, opt) {
  const W = 1920,
    HH = 760,
    TOP = 140,
    FPS = 30;
  const tl = gsap.timeline({ paused: true });
  const cs = getComputedStyle(document.documentElement);
  const col = (v, d) =>
    new THREE.Color((cs.getPropertyValue(v) || d).trim() || d);
  const C = {
    grey: col("--panel", "#dedddf"),
    acc: col("--accent", "#2782cc"),
    ok: col("--ok", "#558141"),
    white: new THREE.Color("#ffffff"),
  };

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(32, W / HH, 0.1, 200);
  let renderer = null;
  if (opt.canvas) {
    const canvas = document.createElement("canvas");
    canvas.className = "gl";
    host.appendChild(canvas);
    renderer = new THREE.WebGLRenderer({
      canvas,
      antialias: true,
      preserveDrawingBuffer: true,
      alpha: false,
    });
    renderer.setPixelRatio(1);
    renderer.setSize(W, HH, false);
    renderer.setClearColor(0xffffff, 1);
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  }
  scene.add(new THREE.HemisphereLight(0xffffff, 0xc9cbd1, 1.7));
  const sun = new THREE.DirectionalLight(0xffffff, 2.3);
  sun.position.set(-7, 15, 9);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  Object.assign(sun.shadow.camera, {
    left: -10,
    right: 10,
    top: 10,
    bottom: -10,
    near: 1,
    far: 50,
  });
  scene.add(sun, sun.target);
  const floor = new THREE.Mesh(
    new THREE.PlaneGeometry(80, 80),
    new THREE.ShadowMaterial({ opacity: 0.13 }),
  );
  floor.rotation.x = -Math.PI / 2;
  floor.receiveShadow = true;
  scene.add(floor);
  const geo = new THREE.BoxGeometry(1, 1, 1);
  const box = (sx, sy, sz, c) => {
    const m = new THREE.Mesh(
      geo,
      new THREE.MeshStandardMaterial({
        color: c.clone(),
        roughness: 0.6,
        metalness: 0.02,
        transparent: true,
      }),
    );
    m.scale.set(sx, sy, sz);
    m.castShadow = true;
    m.receiveShadow = true;
    scene.add(m);
    return m;
  };

  // seeded randomness, never Math.random
  let seed = 7;
  const rng = () => ((seed = (seed * 16807) % 2147483647) - 1) / 2147483646;

  // three layers, top (research) to base (Core); each drops in on its cue
  const stack = { gap: 2.2 };
  const spec = [
    ["New research", "Fast moving", "acc", C.acc, 4.36],
    ["Repeated findings", "Proven over time", "chip", C.grey, 6.54],
    ["DORA Core", "Evergreen guide", "ok", C.ok, 14.2],
  ];
  const layers = spec.map(([label, note, cls, c, at], i) => {
    const p = { a: 0, drop: 3, rot: 0 };
    const mesh = box(5.6, 0.34, 3.4, c);
    const lvl = 2 - i;
    tl.fromTo(
      p,
      { a: 0, drop: 3 },
      {
        a: 1,
        drop: 0,
        duration: 1.1,
        ease: "power3.out",
        immediateRender: false,
      },
      at,
    );
    return {
      p,
      mesh,
      lvl,
      label,
      note,
      cls,
      at,
      y: () => lvl * stack.gap + 0.17 + p.drop,
    };
  });
  // a ghost outline of the whole stack while the title speaks
  const ghost = { a: 0 };
  tl.to(ghost, { a: 1, duration: 0.8, ease: "power2.out" }, 0.32);
  tl.to(ghost, { a: 0, duration: 0.6 }, 4.2);
  const ghosts = [0, 1, 2].map((lvl) => {
    const m = new THREE.LineSegments(
      new THREE.EdgesGeometry(geo),
      new THREE.LineBasicMaterial({ color: 0x9a9b9c, transparent: true }),
    );
    m.scale.set(5.6, 0.34, 3.4);
    m.position.set(0, lvl * 2.2 + 0.17, 0);
    scene.add(m);
    return m;
  });

  // papers slide fast across the research layer: closed form in time
  const papers = Array.from({ length: 7 }, (_, i) => {
    const mesh = box(0.5, 0.05, 0.7, C.white);
    return {
      mesh,
      z: (rng() - 0.5) * 2.4,
      t0: 5.0 + i * 0.27,
      speed: 4.2 + rng() * 1.6,
    };
  });
  const paperA = { a: 0 };
  tl.to(paperA, { a: 1, duration: 0.3 }, 5.0);
  tl.to(paperA, { a: 0, duration: 0.4 }, 14.0);
  // churn: the research layer spins while Core holds still
  tl.to(
    layers[0].p,
    { rot: Math.PI * 4, duration: 3.4, ease: "power1.inOut" },
    10.2,
  );
  // the layers close into one block on the last sentence
  tl.to(stack, { gap: 0.36, duration: 1.8, ease: "power3.inOut" }, 19.2);

  // camera: a slow closed-form orbit, a push-in on the last sentence
  const cam = { r: 13.5, h: 6.8, look: 2.4 };
  tl.to(
    cam,
    { r: 10.5, h: 5.0, look: 1.4, duration: 2.2, ease: "power3.inOut" },
    18.88,
  );

  // HTML pins projected from 3D points
  const pins = [];
  let lay = null;
  if (opt.pins) {
    lay = document.createElement("div");
    lay.className = "pins";
    host.appendChild(lay);
  }
  const pin = (fn, cls, text, on, off) => {
    if (!lay) return;
    const a = document.createElement("div");
    a.className = "anc";
    const e = document.createElement("div");
    e.className = cls;
    e.textContent = text;
    a.appendChild(e);
    lay.appendChild(a);
    pins.push([a, fn]);
    tl.fromTo(
      e,
      { opacity: 0, y: 14 },
      { opacity: 1, y: 0, duration: 0.45, ease: "power2.out" },
      on,
    );
    if (off != null) tl.to(e, { opacity: 0, duration: 0.3 }, off);
  };
  layers.forEach((L, i) => {
    pin(
      () => [3.2, L.y() + 0.3, 1.7],
      "pill " + L.cls,
      L.label,
      L.at + 0.35,
      i < 2 ? 18.7 : null,
    );
    pin(
      () => [3.2, L.y() + 0.3, 1.7],
      "note",
      L.note,
      L.at + 0.5,
      i < 2 ? 18.7 : null,
    );
  });
  pin(
    () => [-3.4, layers[0].y() + 0.9, 0],
    "pill stop",
    "counterproductive churn",
    12.4,
    14.0,
  );
  pin(
    () => [0, stack.gap * 2 + 1.0, 0],
    "pill chip",
    "informed by research, more slowly",
    19.64,
    null,
  );

  // frame-number strip: 12 data cells between two black guards
  let code = null;
  if (opt.code) {
    code = document.createElement("div");
    code.className = "code";
    for (let i = 0; i < 14; i++) code.appendChild(document.createElement("i"));
    host.appendChild(code);
  }

  const v = new THREE.Vector3();
  const draw = () => {
    const t = tl.time();
    const ang = -0.55 + t * 0.028;
    camera.position.set(Math.sin(ang) * cam.r, cam.h, Math.cos(ang) * cam.r);
    camera.lookAt(0, cam.look, 0);
    camera.updateMatrixWorld();
    layers.forEach((L) => {
      L.mesh.position.set(0, L.y(), 0);
      L.mesh.rotation.y = L.p.rot;
      L.mesh.material.opacity = L.p.a;
      L.mesh.visible = L.p.a > 0.01;
    });
    ghosts.forEach((g) => {
      g.material.opacity = ghost.a;
      g.visible = ghost.a > 0.01;
    });
    papers.forEach((P) => {
      const k = t - P.t0;
      const x = k < 0 ? -9 : -2.6 + ((k * P.speed) % 5.2);
      P.mesh.position.set(x, layers[0].y() + 0.2, P.z);
      P.mesh.material.opacity = paperA.a;
      P.mesh.visible = paperA.a > 0.01 && k >= 0;
    });
    if (renderer) renderer.render(scene, camera);
    for (const [a, fn] of pins) {
      v.set(...fn()).project(camera);
      a.style.transform = `translate(${((v.x + 1) / 2) * W}px, ${TOP + ((1 - v.y) / 2) * HH}px)`;
    }
    if (code) {
      const f = Math.round(t * FPS);
      [...code.children].forEach((c, i) => {
        const bit = i === 0 || i === 13 ? 1 : (f >> (11 - (i - 1))) & 1;
        c.style.background = bit ? "#000" : "#fff";
      });
    }
  };
  tl.set({}, {}, 23.775); // pad to the slot so the orbit runs to its end
  tl.eventCallback("onUpdate", draw);
  draw();
  return tl;
};

// The `stack3d` component: lit layers stacked in 3D and drawn with Three.js, each
// dropping in on its cue with its label beside it. The canvas is the only thing
// WebGL draws; a label is DOM text placed by projecting its layer through the
// camera that drew the canvas, so the layout gate judges it like any other text.
// Everything is a function of the scene's time, closed form, so a seek renders
// the frame it names: the paused timeline calls the renderer on each update, and
// an empty `set` at the slot's end pads it to run the whole slot, the seam out
// included. No tween spans the slot: a long one on a scene shifted an earlier
// scene's bar edge by a pixel row between two seeks (cause not found).

// The slab's size in world units, the pitch between slabs, and how far above its
// place a layer starts before it drops in over RISE seconds.
const SLAB = { w: 3.4, h: 0.3, d: 2.4 };
const PITCH = 0.7;
const DROP = 1.6;
const RISE = 0.7;
// The camera's orbit: distance, height and a sway about a base angle, in radians.
const ORBIT = { radius: 9.5, height: 3.4, base: 0.7, sway: 0.35, rate: 0.45 };
// A label stands this many px past its slab's silhouette on the label's side.
const GAP = 28;

export const stack3d = (p, f, x) => {
  const { width: W, height: H } = x.box;
  const at = p.layers.map((l) => +x.time(l).toFixed(6));
  return {
    html: `<canvas class="gl" width="${W}" height="${H}"></canvas>${p.layers
      .map((l, i) => `<div class="lb b${i}">${f.tt(l.label)}</div>`)
      .join("")}`,
    css: `.gl { position: absolute; left: 0; top: 0; width: ${W}px; height: ${H}px; }
.lb { position: absolute; left: 0; top: 0; white-space: nowrap; opacity: 0; font: ${f.titleWeight} var(--size-body)/${f.lh(1.15, "title")} ${f.title}; color: var(--text); ${f.rtl ? "transform: translate(-100%, -50%);" : "transform: translate(0, -50%);"} }`,
    reveals: [],
    script: `        (function () {
          const scope = ${JSON.stringify(x.scope)};
          const canvas = document.querySelector(scope + " .gl");
          const css = getComputedStyle(document.querySelector(scope));
          const ink = (name) => new THREE.Color(css.getPropertyValue(name).trim());
          const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, preserveDrawingBuffer: true });
          renderer.setPixelRatio(1);
          renderer.setSize(${W}, ${H}, false);
          const scene = new THREE.Scene();
          scene.add(new THREE.HemisphereLight(0xffffff, 0x445566, 1.6));
          const key = new THREE.DirectionalLight(0xffffff, 2.2);
          key.position.set(4, 6, 3);
          scene.add(key);
          const camera = new THREE.PerspectiveCamera(32, ${W} / ${H}, 0.1, 50);
          const at = ${JSON.stringify(at)};
          const labels = at.map((_, i) => document.querySelector(scope + " .b" + i));
          const slabs = at.map((_, i) => {
            const color = ink("--accent");
            color.offsetHSL(0, 0, (i - (at.length - 1)) * 0.05);
            const slab = new THREE.Mesh(
              new THREE.BoxGeometry(${SLAB.w}, ${SLAB.h}, ${SLAB.d}),
              new THREE.MeshStandardMaterial({ color, roughness: 0.45, metalness: 0.1, transparent: true }),
            );
            scene.add(slab);
            return slab;
          });
          const place = (i) => (i - (at.length - 1) / 2) * ${PITCH};
          const draw = (t) => {
            const angle = ${ORBIT.base} + ${ORBIT.sway} * Math.sin(t * ${ORBIT.rate});
            camera.position.set(${ORBIT.radius} * Math.sin(angle), ${ORBIT.height}, ${ORBIT.radius} * Math.cos(angle));
            camera.lookAt(0, 0, 0);
            camera.updateMatrixWorld();
            slabs.forEach((slab, i) => {
              const k = Math.min(Math.max((t - at[i]) / ${RISE}, 0), 1);
              const rise = 1 - Math.pow(1 - k, 3);
              slab.position.set(0, place(i) + (1 - rise) * ${DROP}, 0);
              slab.material.opacity = rise;
              slab.visible = k > 0;
              const side = [-1, 1].flatMap((dz) => [-1, 1].map((dy) => slab.position.clone().add(new THREE.Vector3(${f.rtl ? -SLAB.w : SLAB.w} / 2, dy * ${SLAB.h} / 2, dz * ${SLAB.d} / 2)).project(camera)));
              const edge = side.reduce((a, c) => (${f.rtl ? "c.x < a.x" : "c.x > a.x"} ? c : a));
              labels[i].style.left = ((edge.x * 0.5 + 0.5) * ${W} + ${f.rtl ? -GAP : GAP}) + "px";
              labels[i].style.top = ((-slab.position.clone().project(camera).y * 0.5 + 0.5) * ${H}) + "px";
              labels[i].style.opacity = rise;
            });
            renderer.render(scene, camera);
          };
          tl.set({}, {}, ${x.slot});
          tl.eventCallback("onUpdate", () => draw(tl.time()));
          draw(0);
        })();`,
  };
};

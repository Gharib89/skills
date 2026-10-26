// One lit Three.js scene, shared byte for byte by the Remotion and HyperFrames probes.
// draw(t) renders the complete picture at t seconds and keeps no state between calls.
import * as THREE from "three";

export function makeScene(canvas, width, height) {
  const renderer = new THREE.WebGLRenderer({
    canvas,
    antialias: true,
    preserveDrawingBuffer: true,
  });
  renderer.setPixelRatio(1);
  renderer.setSize(width, height, false);
  renderer.shadowMap.enabled = true;
  const scene = new THREE.Scene();
  scene.background = new THREE.Color("#14161c");
  const camera = new THREE.PerspectiveCamera(45, width / height, 0.1, 100);
  scene.add(new THREE.AmbientLight(0xffffff, 0.25));
  const sun = new THREE.DirectionalLight(0xffffff, 2.2);
  sun.position.set(5, 8, 6);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  scene.add(sun);
  const knot = new THREE.Mesh(
    new THREE.TorusKnotGeometry(1.2, 0.38, 256, 48),
    new THREE.MeshStandardMaterial({
      color: "#e07a5f",
      metalness: 0.3,
      roughness: 0.35,
    }),
  );
  knot.castShadow = true;
  knot.position.y = 1.6;
  scene.add(knot);
  const floor = new THREE.Mesh(
    new THREE.PlaneGeometry(30, 30),
    new THREE.MeshStandardMaterial({ color: "#2a2d36" }),
  );
  floor.rotation.x = -Math.PI / 2;
  floor.receiveShadow = true;
  scene.add(floor);
  const boxes = new THREE.InstancedMesh(
    new THREE.BoxGeometry(0.3, 0.3, 0.3),
    new THREE.MeshStandardMaterial({ color: "#81b29a", roughness: 0.5 }),
    400,
  );
  boxes.castShadow = true;
  scene.add(boxes);
  const m = new THREE.Matrix4();
  const q = new THREE.Quaternion();
  const e = new THREE.Euler();
  const p = new THREE.Vector3();
  const s = new THREE.Vector3(1, 1, 1);

  return function draw(t) {
    knot.rotation.set(t * 0.7, t * 1.1, 0);
    for (let i = 0; i < 400; i++) {
      const a = (i / 400) * Math.PI * 2 + t * 0.4;
      const r = 3 + (i % 5) * 0.5;
      p.set(
        Math.cos(a) * r,
        0.2 + 0.6 * Math.abs(Math.sin(a * 3 + t * 2)),
        Math.sin(a) * r,
      );
      q.setFromEuler(e.set(t + i, t * 0.5 + i, 0));
      boxes.setMatrixAt(i, m.compose(p, q, s));
    }
    boxes.instanceMatrix.needsUpdate = true;
    camera.position.set(Math.cos(t * 0.3) * 9, 5, Math.sin(t * 0.3) * 9);
    camera.lookAt(0, 1, 0);
    renderer.render(scene, camera);
  };
}

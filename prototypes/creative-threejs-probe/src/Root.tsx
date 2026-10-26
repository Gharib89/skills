import React, { useState } from "react";
import {
  AbsoluteFill,
  Composition,
  staticFile,
  useCurrentFrame,
  useDelayRender,
  useVideoConfig,
} from "remotion";
import { ThreeCanvas } from "@remotion/three";
import { ThreeWebGPUCanvas } from "@remotion/three/webgpu";
import { Float, Sparkles, Text } from "@react-three/drei";
import { useThree } from "@react-three/fiber";
import { PMREMGenerator } from "three";
import { RoomEnvironment } from "three/examples/jsm/environments/RoomEnvironment.js";

const W = 640;
const H = 360;

// A lit, shadowed exploded stack driven only by the frame.
const Stack: React.FC = () => {
  const frame = useCurrentFrame();
  const gap = 0.2 + 0.6 * Math.min(1, frame / 45);
  return (
    <>
      <ambientLight intensity={0.4} />
      <directionalLight position={[3, 5, 2]} intensity={2} castShadow />
      <group rotation={[0.5, frame / 40, 0]}>
        {[0, 1, 2].map((i) => (
          <mesh
            key={i}
            position={[0, (i - 1) * gap, 0]}
            castShadow
            receiveShadow
          >
            <boxGeometry args={[2, 0.15, 1.4]} />
            <meshStandardMaterial
              color={["#e07a5f", "#3d85c6", "#81b29a"][i]}
            />
          </mesh>
        ))}
      </group>
    </>
  );
};

// Opaque: scene background drawn by three.
const Opaque: React.FC = () => (
  <ThreeCanvas width={W} height={H} shadows camera={{ position: [0, 0, 5] }}>
    <color attach="background" args={["#202840"]} />
    <Stack />
  </ThreeCanvas>
);

// Transparent: alpha canvas over a DOM background (the motioncraft shape).
const Transparent: React.FC = () => (
  <AbsoluteFill style={{ backgroundColor: "#202840" }}>
    <ThreeCanvas
      width={W}
      height={H}
      shadows
      gl={{ alpha: true }}
      camera={{ position: [0, 0, 5] }}
    >
      <Stack />
    </ThreeCanvas>
  </AbsoluteFill>
);

// The rest of the motioncraft shape: transmission plus a PMREM RoomEnvironment on an alpha canvas.
const Env: React.FC = () => {
  const { gl, scene } = useThree();
  React.useEffect(() => {
    const pmrem = new PMREMGenerator(gl);
    scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
  }, [gl, scene]);
  return null;
};
const TransparentHeavy: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{ backgroundColor: "#202840" }}>
      <ThreeCanvas
        width={W}
        height={H}
        shadows
        gl={{ alpha: true }}
        camera={{ position: [0, 0, 5] }}
      >
        <Env />
        <Stack />
        <mesh position={[0, 0, 1.5]} rotation={[0, frame / 30, 0]}>
          <sphereGeometry args={[0.7, 48, 48]} />
          <meshPhysicalMaterial
            transmission={1}
            roughness={0.1}
            thickness={0.5}
          />
        </mesh>
      </ThreeCanvas>
    </AbsoluteFill>
  );
};

// drei components that read state.clock inside useFrame.
const DreiClock: React.FC = () => (
  <ThreeCanvas width={W} height={H} camera={{ position: [0, 0, 5] }}>
    <color attach="background" args={["#202840"]} />
    <ambientLight intensity={1} />
    <Float speed={2} floatIntensity={2}>
      <mesh>
        <boxGeometry args={[1, 1, 1]} />
        <meshStandardMaterial color="#e07a5f" />
      </mesh>
    </Float>
    <Sparkles count={60} scale={4} size={6} speed={1} seed={1} />
  </ThreeCanvas>
);

// troika text via drei, Arabic, local font: is it laid out on the first frame each tab renders?
const ArabicText: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <ThreeCanvas width={W} height={H} camera={{ position: [0, 0, 5] }}>
      <color attach="background" args={["#202840"]} />
      <Text
        font={staticFile("arabic.ttf")}
        fontSize={0.6}
        color="#ffffff"
        position={[0, 0, 0]}
        rotation={[0, frame / 60, 0]}
      >
        {"مرحبا بالعالم"}
      </Text>
    </ThreeCanvas>
  );
};

// Same, but each tab holds its frame until troika reports the layout is synced.
const ArabicTextSynced: React.FC = () => {
  const frame = useCurrentFrame();
  const { delayRender, continueRender } = useDelayRender();
  const [handle] = useState(() => delayRender("troika sync"));
  const done = React.useRef(false);
  const onSynced = React.useCallback(() => {
    if (!done.current) {
      done.current = true;
      continueRender(handle);
    }
  }, [continueRender, handle]);
  return (
    <ThreeCanvas width={W} height={H} camera={{ position: [0, 0, 5] }}>
      <color attach="background" args={["#202840"]} />
      <SyncedText rotationY={frame / 60} onSynced={onSynced} />
    </ThreeCanvas>
  );
};
// Inside the canvas: after troika's layout lands, draw once more (frameloop is 'never' in a render), then release the frame.
const SyncedText: React.FC<{ rotationY: number; onSynced: () => void }> = ({
  rotationY,
  onSynced,
}) => {
  const advance = useThree((s) => s.advance);
  const onSync = React.useCallback(() => {
    advance(performance.now());
    onSynced();
  }, [advance, onSynced]);
  return (
    <Text
      font={staticFile("arabic.ttf")}
      fontSize={0.6}
      color="#ffffff"
      rotation={[0, rotationY, 0]}
      onSync={onSync}
    >
      {"مرحبا بالعالم"}
    </Text>
  );
};

const Backend: React.FC<{ onName: (n: string) => void }> = ({ onName }) => {
  const gl = useThree((s) => s.gl) as unknown as {
    backend?: { isWebGPUBackend?: boolean; isWebGLBackend?: boolean };
  };
  React.useEffect(() => {
    const b = gl.backend;
    onName(
      b?.isWebGPUBackend
        ? "WebGPU backend"
        : b?.isWebGLBackend
          ? "WebGL2 fallback backend"
          : "unknown backend",
    );
  }, [gl, onName]);
  return null;
};

const WebGPU: React.FC = () => {
  const [name, setName] = useState("pending");
  const { delayRender, continueRender } = useDelayRender();
  const [handle] = useState(() => delayRender("backend name"));
  const onName = React.useCallback(
    (n: string) => {
      setName(n);
      continueRender(handle);
    },
    [continueRender, handle],
  );
  return (
    <AbsoluteFill style={{ backgroundColor: "#202840" }}>
      <ThreeWebGPUCanvas width={W} height={H} camera={{ position: [0, 0, 5] }}>
        <Backend onName={onName} />
        <Stack />
      </ThreeWebGPUCanvas>
      <div
        id="backend"
        style={{
          position: "absolute",
          top: 10,
          left: 10,
          color: "white",
          fontSize: 28,
          fontFamily: "sans-serif",
        }}
      >
        {name}
      </div>
    </AbsoluteFill>
  );
};

const Renderer: React.FC<{ onName: (n: string) => void }> = ({ onName }) => {
  const gl = useThree((s) => s.gl);
  React.useEffect(() => {
    const c = gl.getContext();
    const ext = c.getExtension("WEBGL_debug_renderer_info");
    onName(
      String(
        ext
          ? c.getParameter(ext.UNMASKED_RENDERER_WEBGL)
          : c.getParameter(c.RENDERER),
      ),
    );
  }, [gl, onName]);
  return null;
};
const GLInfo: React.FC = () => {
  const [name, setName] = useState("pending");
  const { delayRender, continueRender } = useDelayRender();
  const [handle] = useState(() => delayRender("renderer name"));
  const onName = React.useCallback(
    (n: string) => {
      setName(n);
      continueRender(handle);
    },
    [continueRender, handle],
  );
  return (
    <AbsoluteFill style={{ backgroundColor: "#202840" }}>
      <ThreeCanvas width={W} height={H}>
        <Renderer onName={onName} />
      </ThreeCanvas>
      <div
        style={{
          position: "absolute",
          top: 10,
          left: 10,
          right: 10,
          color: "white",
          fontSize: 20,
          fontFamily: "sans-serif",
        }}
      >
        {name}
      </div>
    </AbsoluteFill>
  );
};

export const Root: React.FC = () => (
  <>
    <Composition
      id="GLInfo"
      component={GLInfo}
      durationInFrames={1}
      fps={30}
      width={W}
      height={H}
    />
    <Composition
      id="Opaque"
      component={Opaque}
      durationInFrames={60}
      fps={30}
      width={W}
      height={H}
    />
    <Composition
      id="Transparent"
      component={Transparent}
      durationInFrames={60}
      fps={30}
      width={W}
      height={H}
    />
    <Composition
      id="TransparentHeavy"
      component={TransparentHeavy}
      durationInFrames={60}
      fps={30}
      width={W}
      height={H}
    />
    <Composition
      id="DreiClock"
      component={DreiClock}
      durationInFrames={60}
      fps={30}
      width={W}
      height={H}
    />
    <Composition
      id="ArabicText"
      component={ArabicText}
      durationInFrames={60}
      fps={30}
      width={W}
      height={H}
    />
    <Composition
      id="ArabicTextSynced"
      component={ArabicTextSynced}
      durationInFrames={60}
      fps={30}
      width={W}
      height={H}
    />
    <Composition
      id="WebGPU"
      component={WebGPU}
      durationInFrames={30}
      fps={30}
      width={W}
      height={H}
    />
  </>
);

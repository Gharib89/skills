import {
  AbsoluteFill,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
  Easing,
} from "remotion";
import { loadFont } from "@remotion/fonts";
import { getLength, getPointAtLength } from "@remotion/paths";

loadFont({
  family: "PlexArabic",
  url: staticFile("arabic.ttf"),
  weight: "700",
});

const PATH = "M 160 760 C 460 420, 760 980, 1060 640 S 1560 360, 1760 620";
const LEN = getLength(PATH);
const COLORS = ["#e07a5f", "#f2cc8f", "#81b29a", "#3d85c6", "#c08497"];
const SPRING = { damping: 9, stiffness: 120, mass: 1 };

export const Scene = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const draw = interpolate(frame, [45, 135], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.inOut(Easing.cubic),
  });
  const dot = getPointAtLength(PATH, LEN * draw);
  const ar = spring({ frame: frame - 150, fps, config: SPRING });
  return (
    <AbsoluteFill style={{ background: "#14161c" }}>
      {COLORS.map((c, i) => {
        const s = spring({ frame: frame - 6 - i * 5, fps, config: SPRING });
        return (
          <div
            key={i}
            style={{
              position: "absolute",
              left: 200 + i * 320,
              top: 140,
              width: 240,
              height: 240,
              borderRadius: 32,
              background: c,
              transform: `translateY(${(1 - s) * 300}px) scale(${0.4 + 0.6 * s}) rotate(${(1 - s) * 25}deg)`,
            }}
          />
        );
      })}
      <svg width={1920} height={1080} style={{ position: "absolute" }}>
        <path
          d={PATH}
          fill="none"
          stroke="#f2cc8f"
          strokeWidth={10}
          strokeLinecap="round"
          strokeDasharray={LEN}
          strokeDashoffset={LEN * (1 - draw)}
        />
        <circle cx={dot.x} cy={dot.y} r={22} fill="#e07a5f" />
      </svg>
      <div
        dir="rtl"
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 860,
          textAlign: "center",
          fontFamily: "PlexArabic",
          fontWeight: 700,
          fontSize: 84,
          color: "#fafafa",
          opacity: Math.min(1, ar * 1.5),
          transform: `translateY(${(1 - ar) * 120}px)`,
        }}
      >
        الـ hook بيوقف rm -rf قبل ما يتنفذ
      </div>
    </AbsoluteFill>
  );
};

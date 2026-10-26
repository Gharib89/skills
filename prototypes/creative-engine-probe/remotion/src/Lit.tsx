import { useLayoutEffect, useRef } from "react";
import { AbsoluteFill, useCurrentFrame, useVideoConfig } from "remotion";
// @ts-expect-error plain JS module shared with the HyperFrames probe
import { makeScene } from "../../lit/scene.mjs";

export const Lit = () => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const canvas = useRef<HTMLCanvasElement>(null);
  const draw = useRef<((t: number) => void) | null>(null);
  useLayoutEffect(() => {
    if (!draw.current && canvas.current)
      draw.current = makeScene(canvas.current, width, height);
    draw.current?.(frame / fps);
  }, [frame, fps, width, height]);
  return (
    <AbsoluteFill>
      <canvas ref={canvas} width={width} height={height} />
    </AbsoluteFill>
  );
};

import { AbsoluteFill } from "remotion";

// Prints the WebGL renderer string Chrome picked for this render.
const renderer = (() => {
  const gl = document.createElement("canvas").getContext("webgl");
  if (!gl) return "no webgl";
  const ext = gl.getExtension("WEBGL_debug_renderer_info");
  return ext
    ? String(gl.getParameter(ext.UNMASKED_RENDERER_WEBGL))
    : String(gl.getParameter(gl.RENDERER));
})();

export const GpuProbe = () => {
  console.log("WEBGL_RENDERER " + renderer);
  return (
    <AbsoluteFill style={{ background: "white", fontSize: 40, padding: 40 }}>
      {renderer}
    </AbsoluteFill>
  );
};

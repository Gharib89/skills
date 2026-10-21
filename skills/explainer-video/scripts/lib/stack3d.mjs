// The `stack3d` component's props at compile: lit layers drawn in 3D, each
// rising on its cue with a label. The composer lays the stack out and moves the
// camera, so the scene file holds no coordinates.
import { CUE, known, list, named } from "./props.mjs";

// The layers a stack holds: past six a layer's label no longer fits beside it.
export const STACK3D = { min: 2, max: 6 };

// Throws the first reason the props `p` are not a stack for the scene's
// sentences in spoken form, `said`.
export function checkStack3d(p, said) {
  list("stack3d", p.layers, "layers", said, [STACK3D.min, STACK3D.max]);
  for (const l of p.layers) {
    named("stack3d", l.label, "a label per layer");
    known("a stack3d layer", l, [...CUE, "label"]);
  }
}

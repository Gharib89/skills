// The `canvas` component's props at compile: 2 to 6 items, each a title and a
// body on its own cue, in the order the camera visits them. lib/visuals.mjs
// holds the entry.
import { fail, list, named, place } from "./props.mjs";

export function checkCanvas(p, said) {
  list("canvas", p.items, "items", said, [2, 6]);
  for (const [i, x] of p.items.entries()) {
    named("canvas", x.title, "a title per item");
    named("canvas", x.body, "a body per item");
    if (i && place(x, said) < place(p.items[i - 1], said))
      fail(
        `canvas item ${i + 1} cues before item ${i}: the camera visits the items in the order written`,
      );
  }
}

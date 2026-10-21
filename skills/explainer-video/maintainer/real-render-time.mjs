// Maintainer only: the checks of real-render.mjs that prove a scene's picture is
// a function of time, one a component: a browser's cursor, an excerpt's lit
// sentence, a stack3d scene's WebGL canvas. Each seeks frames of the whole
// composition (`seek(t, name, software)` returns the PNG's bytes) and reports
// through `check(name, ok, detail)`.

const at = (t) => +t.toFixed(3);
const start = (whole, id) => whole.scenes.find((s) => s.id === id).start;

// The cursor's place: each browser scene's frame 1.35 s in, the cursor mid-move
// to the field, seeked twice, matches byte for byte and differs from the frame
// 0.2 s later.
async function cursor({ whole, seek, check, browsers }) {
  const cursors = [];
  for (const { id } of browsers) {
    const t = at(start(whole, id) + 1.35);
    const a = await seek(t, "cursor-a");
    const b = await seek(t, "cursor-b");
    const later = await seek(at(t + 0.2), "cursor-later");
    cursors.push([id, a.equals(b), !a.equals(later)]);
  }
  check(
    "cursor",
    cursors.every(([, same, moved]) => same && moved),
    cursors
      .map(
        ([id, same, moved]) =>
          `${id}: ${same ? "equal" : "DIFFERENT"} on two seeks, ${moved ? "moves" : "STILL"} 0.2 s later`,
      )
      .join("; "),
  );
}

// A sentence is lit: each excerpt scene's frame mid-way through the light-up on
// its emphasis cue (sentence 2, a third of the way in), seeked twice, matches
// byte for byte and differs from the frame before it.
async function lit({ whole, seek, check, excerpts }) {
  const lighting = [];
  for (const { id } of excerpts) {
    const from = start(whole, id);
    const t = at(from + 1.55);
    const a = await seek(t, "lit-a");
    const b = await seek(t, "lit-b");
    const before = await seek(at(from + 1.0), "lit-before");
    lighting.push([id, a.equals(b), !a.equals(before)]);
  }
  check(
    "lit",
    lighting.every(([, same, moved]) => same && moved),
    lighting
      .map(
        ([id, same, moved]) =>
          `${id}: ${same ? "equal" : "DIFFERENT"} on two seeks, ${moved ? "differs" : "SAME"} from before its cue`,
      )
      .join("; "),
  );
}

// The WebGL canvas: each stack3d scene's frame 1.3 s in, a layer mid-drop,
// rendered twice on SwiftShader as the determinism gate does, matches byte for
// byte, and differs from the frame 0.2 s later. The canvas is drawn, not blank:
// its frame, and the slot's last, differ from the first, before any layer is in.
async function webgl({ whole, seek, check, stacks }) {
  const drawn = [];
  for (const { id } of stacks) {
    const { start: from, slot } = whole.scenes.find((s) => s.id === id);
    const t = at(from + 1.3);
    const a = await seek(t, "stack-a", true);
    const b = await seek(t, "stack-b", true);
    const later = await seek(at(t + 0.2), "stack-later", true);
    const empty = await seek(at(from + 0.05), "stack-empty", true);
    const last = await seek(at(from + slot - 0.04), "stack-last", true);
    drawn.push([
      id,
      a.equals(b),
      !a.equals(later),
      !a.equals(empty) && !last.equals(empty),
    ]);
  }
  check(
    "webgl",
    drawn.every((d) => d.slice(1).every(Boolean)),
    drawn
      .map(
        ([id, same, moves, filled]) =>
          `${id}: ${same ? "equal" : "DIFFERENT"} on two seeks, ${moves ? "moves" : "STILL"} 0.2 s later, ${filled ? "drawn" : "BLANK"}`,
      )
      .join("; "),
  );
}

export async function timeChecks(ctx) {
  await cursor(ctx);
  await lit(ctx);
  await webgl(ctx);
}

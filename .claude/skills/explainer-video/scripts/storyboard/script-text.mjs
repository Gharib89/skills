// Reading and rewriting script.md in place, for board.mjs: where each scene's
// narration sits, and a kept term respelt across the title, narration and screen text.
import { mapScreen, rename, respell } from "../lib/terms.mjs";

// Each scene's narration block in script.md: the lines after `### Narration`
// up to `### Visual`, edge blank lines left out.
export function narrationBlocks(lines) {
  const blocks = {};
  let id = null;
  let from = null;
  lines.forEach((line, i) => {
    const m = line.match(/^## Scene\s+([A-Za-z0-9-]+)\s+·\s+(.+?)\s*$/);
    if (m) id = m[1];
    else if (/^### Narration\s*$/.test(line)) from = i + 1;
    else if (/^### Visual\s*$/.test(line) && id && from !== null) {
      let a = from;
      let b = i;
      while (a < b && !lines[a].trim()) a++;
      while (b > a && !lines[b - 1].trim()) b--;
      blocks[id] = { from: a, to: b };
      from = null;
    }
  });
  return blocks;
}

// A scene's `### Visual` JSON in script.md, changed in place by `edit(visual)`:
// a block of several lines stays indented, a one-line block stays one line.
export function editVisual(lines, id, edit) {
  let on = false;
  let part = null;
  let fence = null;
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^## Scene\s+([A-Za-z0-9-]+)\s+·/);
    if (m) [on, part] = [m[1] === id, null];
    else if (!on) continue;
    else if (/^### /.test(lines[i]))
      part = lines[i].match(/^### (Visual)\s*$/)?.[1] ?? null;
    else if (
      part === "Visual" &&
      fence === null &&
      /^```json\s*$/.test(lines[i])
    )
      fence = i + 1;
    else if (part === "Visual" && fence !== null && /^```\s*$/.test(lines[i])) {
      let visual;
      try {
        visual = JSON.parse(lines.slice(fence, i).join("\n"));
      } catch (e) {
        throw new Error(`script.md visual block for ${id} is not JSON`);
      }
      if (edit(visual) === false) return;
      const out = JSON.stringify(visual, null, i - fence > 1 ? 2 : undefined);
      lines.splice(fence, i - fence, ...out.split("\n"));
      return;
    }
  }
  throw new Error(`script.md has no visual block for ${id}`);
}

// Kept terms spelled anew across script.md, in place, from a Map of term to
// new spelling: the title, each scene's narration (its cites aside) and its
// visual's screen text. The ids of the scenes they changed.
export function renameKept(lines, spellings) {
  const swap = (t) => rename(t, spellings);
  const touched = new Set();
  let id = null;
  let part = null;
  let fence = null;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const m = line.match(/^## Scene\s+([A-Za-z0-9-]+)\s+·/);
    if (m) [id, part] = [m[1], null];
    else if (!id && /^# /.test(line)) lines[i] = swap(line);
    else if (/^### /.test(line))
      part = line.match(/^### (Narration|Visual)\s*$/)?.[1] ?? null;
    else if (part === "Narration" && line.trim()) {
      const next = line.replace(
        /^(.*?)((?:\s*\[[^\]]*\])*\s*)$/,
        (_, text, cites) => respell(text, spellings) + cites,
      );
      if (next !== line) {
        lines[i] = next;
        touched.add(id);
      }
    } else if (part === "Visual" && fence === null && /^```json\s*$/.test(line))
      fence = i + 1;
    else if (part === "Visual" && fence !== null && /^```\s*$/.test(line)) {
      const visual = JSON.parse(lines.slice(fence, i).join("\n"));
      const next = mapScreen(visual, swap);
      if (JSON.stringify(next) !== JSON.stringify(visual)) {
        const out = JSON.stringify(next, null, i - fence > 1 ? 2 : undefined);
        lines.splice(fence, i - fence, ...out.split("\n"));
        i = fence + out.split("\n").length;
        touched.add(id);
      }
      [part, fence] = [null, null];
    }
  }
  return [...touched];
}

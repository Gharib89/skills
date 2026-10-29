// What a board records of the project, and the board whose answers approved
// the look: shared by the board's build guard (board.mjs) and the render,
// which compare the project as it stands with a board in the same words.
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

export const sha = (bytes) =>
  crypto.createHash("sha256").update(bytes).digest("hex").slice(0, 16);

// Every file under kit/, nested ones too: each one's name and bytes, sorted.
function kitHash(proj) {
  const dir = path.join(proj, "kit");
  const h = crypto.createHash("sha256");
  if (fs.existsSync(dir))
    for (const f of fs.readdirSync(dir, { recursive: true }).sort())
      if (fs.statSync(path.join(dir, f)).isFile())
        h.update(`${f}\0`).update(fs.readFileSync(path.join(dir, f)));
  return h.digest("hex").slice(0, 16);
}

// Each file under assets/ but the two timing writes, by name: a scene may add
// one, but one that changes or goes changes every scene that uses it.
function assetHashes(proj) {
  const dir = path.join(proj, "assets");
  if (!fs.existsSync(dir)) return {};
  return Object.fromEntries(
    fs
      .readdirSync(dir, { recursive: true })
      .sort()
      .filter(
        (f) =>
          !["narration.wav", "gsap.min.js"].includes(f) &&
          fs.statSync(path.join(dir, f)).isFile(),
      )
      .map((f) => [f, sha(fs.readFileSync(path.join(dir, f)))]),
  );
}

// The project `proj` as a board records it: `hashes` maps each of `ids` to its
// composition file's hash, beside the kit's, over.html's (null without one)
// and each asset's.
export function projectHashes(proj, ids) {
  const file = (name) => path.join(proj, "compositions", name);
  return {
    hashes: Object.fromEntries(
      ids.map((id) => [id, sha(fs.readFileSync(file(`${id}.html`)))]),
    ),
    kit: kitHash(proj),
    over: fs.existsSync(file("over.html"))
      ? sha(fs.readFileSync(file("over.html")))
      : null,
    assets: assetHashes(proj),
  };
}

// Each scene's voiced words joined, the narration a board records.
export const voicedText = (voice) =>
  new Map(
    voice.scenes.map((v) => [v.id, v.words.map((w) => w.text).join(" ")]),
  );

// What changed since board `prev`, as `<ids>`, then `the kit`, `over.html`
// and `assets/<file>`: a scene whose file or narration differs, or that was
// added or went, but for a later chapter's scene added (`chapterOf` maps each
// id to its chapter) and the scenes in `named`. `now` is projectHashes';
// `voiced` is voicedText's.
export function changedSince(prev, now, voiced, chapterOf, named = []) {
  const was = new Map(
    prev.scenes.map((s) => [s.id, `${s.hash} ${s.narration}`]),
  );
  const is = new Map(
    Object.entries(now.hashes).map(([id, h]) => [id, `${h} ${voiced.get(id)}`]),
  );
  const changed = [...new Set([...was.keys(), ...is.keys()])].filter(
    (id) =>
      !named.includes(id) &&
      was.get(id) !== is.get(id) &&
      !(!was.has(id) && chapterOf[id] > 1),
  );
  if (now.kit !== prev.kit) changed.push("the kit");
  if (now.over !== prev.over) changed.push("over.html");
  for (const [f, h] of Object.entries(prev.assets))
    if (now.assets[f] !== h) changed.push(`assets/${f}`);
  return changed;
}

// The board whose answers approved the look, `{ n, board }`, or null: the
// latest answers that `board apply` printed `board: approved` for (an approval
// with no direction, look or scene note), with no later answers asking for a
// direction or a look. Later scene notes leave it standing, and a later
// approval (on a later chapter's board) takes its place.
export function approvedBoard(run) {
  const dir = path.join(run, "board");
  if (!fs.existsSync(dir)) return null;
  const read = (f) => JSON.parse(fs.readFileSync(path.join(dir, f), "utf8"));
  let n = null;
  for (const k of fs
    .readdirSync(dir)
    .flatMap((f) => /^answers-(\d+)\.json$/.exec(f)?.[1] ?? [])
    .map(Number)
    .sort((a, b) => a - b)) {
    const a = read(`answers-${k}.json`);
    if (a.direction || a.look) n = null;
    else if (a.approve && !a.scenes.length) n = k;
  }
  return n && { n, board: read(`${n}.json`) };
}

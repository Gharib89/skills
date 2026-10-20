// `board.mjs apply`: the human's answers to the latest board version, checked
// against that board, written to board/answers-<n>.json, and their edits (narration,
// kept terms, menu picks) written into script.md. Prints one line per card, per
// pick, per brief change and per kept term, then `board: approved` or `board:
// redo <ids>[; brief <args>]`. `fail(why)` ends the run.
import fs from "node:fs";
import path from "node:path";
import { readAnswers } from "./answers-text.mjs";
import { applyPick } from "./menus.mjs";
import { editVisual, narrationBlocks, renameKept } from "./script-text.mjs";

export function applyAnswers(run, board, n, raw, fail) {
  const at = (...p) => path.join(run, ...p);
  const answers = readAnswers(raw, n, fail);
  if (answers.version !== n)
    fail(`answers for board ${answers.version}, the latest is board ${n}`);
  const ids = board.scenes.map((c) => c.id);
  for (const s of answers.scenes)
    if (!ids.includes(s.id)) fail(`the answers name no scene ${s.id}`);
  for (const s of answers.scenes)
    if (!["approve", "revise"].includes(s.choice))
      fail(`scene ${s.id} has no answer`);
  for (const id of ids)
    if (!answers.scenes.some((s) => s.id === id))
      fail(`the answers miss card ${id}`);
  answers.scenes = ids.map((id) => {
    const s = answers.scenes.find((x) => x.id === id);
    const menus = board.scenes.find((c) => c.id === id).menus;
    // Only a pick that differs from the card's own is a change.
    const picks = {};
    for (const [menu, value] of Object.entries(s.picks ?? {})) {
      if (!menus?.[menu]) fail(`scene ${id} has no ${menu} menu`);
      if (!menus[menu].options.includes(value))
        fail(`scene ${id} has no ${menu} option ${value}`);
      if (value !== menus[menu].pick) picks[menu] = value;
    }
    return {
      id,
      choice: s.choice,
      note: s.note ?? "",
      narration: s.narration ?? "",
      picks,
    };
  });
  answers.brief ??= [];
  if (board.kept) answers.kept ??= [];
  for (const k of answers.kept ?? []) {
    if (!board.kept?.includes(k.term))
      fail(`the answers edit ${k.term}, which board ${n} does not keep`);
    if (!k.to?.trim()) fail(`kept term ${k.term} is edited to nothing`);
  }
  fs.writeFileSync(
    at("board", `answers-${n}.json`),
    JSON.stringify(answers, null, 2) + "\n",
  );

  const edited = (s) =>
    s.narration.trim() &&
    s.narration !== board.scenes.find((c) => c.id === s.id).narration;
  const edits = answers.scenes.filter(edited);
  if (edits.length) {
    const lines = fs.readFileSync(at("script.md"), "utf8").split("\n");
    const blocks = narrationBlocks(lines);
    for (const s of edits)
      if (!blocks[s.id]) fail(`script.md has no narration block for ${s.id}`);
    for (const s of edits.sort((a, b) => blocks[b.id].from - blocks[a.id].from))
      lines.splice(
        blocks[s.id].from,
        blocks[s.id].to - blocks[s.id].from,
        ...s.narration.split("\n"),
      );
    fs.writeFileSync(at("script.md"), lines.join("\n"));
  }
  const renamed = new Set();
  if (answers.kept?.length) {
    const lines = fs.readFileSync(at("script.md"), "utf8").split("\n");
    const spellings = new Map(answers.kept.map((k) => [k.term, k.to.trim()]));
    for (const id of renameKept(lines, spellings)) renamed.add(id);
    fs.writeFileSync(at("script.md"), lines.join("\n"));
  }
  const picked = answers.scenes.filter((s) => Object.keys(s.picks).length);
  if (picked.length) {
    const lines = fs.readFileSync(at("script.md"), "utf8").split("\n");
    try {
      for (const s of picked)
        for (const [menu, value] of Object.entries(s.picks))
          editVisual(lines, s.id, (v) => applyPick(v, menu, value));
    } catch (e) {
      fail(e.message);
    }
    fs.writeFileSync(at("script.md"), lines.join("\n"));
  }
  for (const s of answers.scenes) {
    console.log(
      `board ${s.id}: ${s.choice === "approve" ? "approve" : `revise: ${s.note || "no note"}`}${edited(s) ? ", narration edited" : ""}`,
    );
    for (const [menu, value] of Object.entries(s.picks))
      console.log(`board ${s.id} pick: ${menu}=${value}`);
  }
  for (const a of answers.brief) console.log(`board brief: ${a}`);
  for (const k of answers.kept ?? [])
    console.log(`board kept: ${k.term} -> ${k.to.trim()}`);
  // An approved card whose narration, kept terms or picks changed still needs
  // its scene redone.
  const redo = answers.scenes
    .filter(
      (s) =>
        s.choice === "revise" ||
        edited(s) ||
        renamed.has(s.id) ||
        Object.keys(s.picks).length,
    )
    .map((s) => s.id);
  console.log(
    !redo.length && !answers.brief.length && !answers.kept?.length
      ? "board: approved"
      : `board: redo ${redo.join(",") || "none"}${answers.brief.length ? `; brief ${answers.brief.join(" ")}` : ""}`,
  );
}

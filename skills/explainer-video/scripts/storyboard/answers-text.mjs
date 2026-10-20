// An answers file read into the answers document of board-data.md, for
// board.mjs apply: the document itself as JSON, or the text the page copies.
// `n` is the latest board's version, named when the text was cut to fit a
// comment; `fail(why)` ends the run.
export function readAnswers(raw, n, fail) {
  if (raw.trimStart().startsWith("{")) return JSON.parse(raw);
  const lines = raw.split("\n");
  if (lines.some((l) => l.startsWith("[cut to fit:")))
    fail(
      `the answers were cut to fit a comment: read answers/board-${n} from the database`,
    );
  const head = lines[0].match(/^explainer-video: board (\d+) answers/);
  if (!head) fail("not an answers text: its first line is not the header");
  const answers = {
    version: Number(head[1]),
    submittedAt: new Date().toISOString(),
    scenes: [],
    brief: [],
  };
  let card = null;
  let inNarration = false;
  for (const line of lines.slice(1)) {
    let m;
    if ((m = line.match(/^([A-Za-z0-9-]+): (Approve|Revise)$/))) {
      card = {
        id: m[1],
        choice: m[2].toLowerCase(),
        note: "",
        narration: "",
        picks: {},
      };
      answers.scenes.push(card);
      inNarration = false;
    } else if (card && (m = line.match(/^ {2}note: (.*)$/))) {
      card.note = m[1];
      inNarration = false;
    } else if (card && (m = line.match(/^ {2}pick: ([a-z]+)=(.+)$/))) {
      card.picks[m[1]] = m[2];
      inNarration = false;
    } else if (card && line === "  narration:") {
      inNarration = true;
    } else if (inNarration && line.startsWith("    ")) {
      card.narration += (card.narration ? "\n" : "") + line.slice(4);
    } else if ((m = line.match(/^Brief: (.+)$/))) {
      answers.brief.push(m[1]);
      inNarration = false;
    } else if ((m = line.match(/^Kept: (.+?) -> (.+)$/))) {
      (answers.kept ??= []).push({ term: m[1], to: m[2] });
      inNarration = false;
    } else if (line.trim()) fail(`cannot read this answers line: ${line}`);
  }
  return answers;
}

// An answers file read into the answers document of board/board-data.md, for
// board.mjs apply: the document itself as JSON, or the answers text the page's
// copy button and Submit comment carry. Throws the reason it cannot read it.
const HEAD = /^creative-video: board (\d+) answers/;
const LINE = /^([a-z0-9-]+): (.*)$/;

// `{ version, submittedAt, approve, direction, look, scenes: [{ id, note }] }`.
export function readAnswers(text) {
  return text.trimStart().startsWith("{") ? fromJson(text) : fromText(text);
}

function fromJson(text) {
  let v;
  try {
    v = JSON.parse(text);
  } catch (e) {
    throw new Error(`the answers document is not valid JSON (${e.message})`);
  }
  if (!Number.isInteger(v.version))
    throw new Error("the answers document has no version");
  if (v.scenes !== undefined && !Array.isArray(v.scenes))
    throw new Error("the answers document's scenes is not a list");
  return {
    version: v.version,
    submittedAt: v.submittedAt ?? new Date().toISOString(),
    approve: v.approve === true,
    direction: v.direction || null,
    look: String(v.look ?? ""),
    scenes: (v.scenes ?? []).map((s) => ({
      id: String(s.id),
      note: String(s.note ?? ""),
    })),
  };
}

function fromText(text) {
  const lines = text.split("\n");
  const head = lines[0].match(HEAD);
  if (!head)
    throw new Error("not an answers text: its first line is not the header");
  const version = Number(head[1]);
  if (lines.some((l) => l.startsWith("[cut to fit:")))
    throw new Error(
      `the answers were cut to fit a comment: read answers/board-${version} from the database`,
    );
  const answers = {
    version,
    submittedAt: new Date().toISOString(),
    approve: false,
    direction: null,
    look: "",
    scenes: [],
  };
  // A note or the look continues on lines indented two spaces.
  let open = null;
  for (const line of lines.slice(1)) {
    let m;
    if (open && line.startsWith("  ")) {
      open.append(line.slice(2));
    } else if (line === "Approved: the look") {
      answers.approve = true;
      open = null;
    } else if ((m = line.match(/^Direction: ([a-z0-9-]+)$/))) {
      answers.direction = m[1];
      open = null;
    } else if ((m = line.match(/^Look: (.*)$/))) {
      answers.look = m[1];
      open = { append: (l) => (answers.look += `\n${l}`) };
    } else if ((m = line.match(LINE))) {
      const scene = { id: m[1], note: m[2] };
      answers.scenes.push(scene);
      open = { append: (l) => (scene.note += `\n${l}`) };
    } else if (line.trim()) {
      throw new Error(`cannot read this answers line: ${line}`);
    }
  }
  return answers;
}

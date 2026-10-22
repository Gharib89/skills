// A scene file with sections, shared by the compile, check, render and board
// tests: roles and planned seconds per scene, a title visual each.
export const LAYOUT = [
  { id: "hook", role: "hook", seconds: 15 },
  { id: "why", role: "context", seconds: 15 },
  { id: "one", role: "section", seconds: 8 },
  { id: "one-a", role: "point", seconds: 15 },
  { id: "one-b", role: "point", seconds: 15 },
  { id: "two", role: "section", seconds: 8 },
  { id: "two-a", role: "point", seconds: 15 },
  { id: "two-b", role: "point", seconds: 15 },
  { id: "three", role: "section", seconds: 8 },
  { id: "three-a", role: "point", seconds: 15 },
  { id: "three-b", role: "point", seconds: 15 },
  { id: "recap", role: "recap", seconds: 15 },
  { id: "bye", role: "end", seconds: 15 },
];

// The scene file for `layout`: one `# title`, the header, and per scene its
// role line, two narrated sentences and a title visual.
export function sectionFile(layout = LAYOUT) {
  return [
    "# How a long video is cut",
    "language: en",
    "narrator: am_fenrir",
    "style: claude-code",
    "",
    ...layout.flatMap((s) => [
      `## Scene ${s.id} · Scene ${s.id}`,
      `role: ${s.role} · ${s.seconds} s`,
      "",
      "### Narration",
      `1. This is ${s.id} of the long video. [no-claim]`,
      "2. It says one thing. [no-claim]",
      "",
      "### Visual",
      "```json",
      JSON.stringify({
        component: "title",
        props: { title: `Scene ${s.id}` },
      }),
      "```",
      "",
    ]),
  ].join("\n");
}

// `layout` with the scene at `id` changed by `patch`, or dropped by `null`.
export const edit = (id, patch, layout = LAYOUT) =>
  layout.flatMap((s) =>
    s.id !== id ? [s] : patch === null ? [] : [{ ...s, ...patch }],
  );

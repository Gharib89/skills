// The captions gate (gates/captions.mjs): the cues a composition draws, and
// what the timeline's words, those cues and the SRT leave between them.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  captionFindings,
  cuesOf,
} from "../../skills/creative-video/scripts/gates/captions.mjs";
import { CUE_CHARS } from "../../skills/creative-video/scripts/render/cues.mjs";
import { srtText } from "../../skills/creative-video/scripts/render/delivery.mjs";

const cueDiv = (start, duration, words) =>
  `<div class="cue clip" data-start="${start}" data-duration="${duration}" data-track-index="3">${words
    .map((w) => `<span class="w" data-at="0">${w}</span>`)
    .join(" ")}</div>`;

test("the cues read back from the composition, their words unescaped and inner tags dropped", () => {
  const html = [
    "<div class='scene'>",
    cueDiv(0, 1.5, ["Tom", "&amp;", "<b>Jerry</b>"]),
    cueDiv(1.5, 0.75, ["&lt;div&gt;", "&quot;quoted&quot;"]),
    "</div>",
  ].join("\n");
  assert.deepEqual(cuesOf(html), [
    { start: 0, end: 1.5, text: "Tom & Jerry" },
    { start: 1.5, end: 2.25, text: '<div> "quoted"' },
  ]);
});

const timeline = {
  total: 2,
  scenes: [
    {
      id: "hook",
      start: 0,
      duration: 2,
      words: [
        { text: "One", start: 0, end: 0.5 },
        { text: "two", start: 0.5, end: 1 },
        { text: "three", start: 1, end: 1.5 },
      ],
    },
  ],
};
const cues = [
  { start: 0, end: 1, text: "One two" },
  { start: 1, end: 1.8, text: "three" },
];

test("words in order inside their scene, cues in bounds and the SRT their copy find nothing", () => {
  assert.deepEqual(
    captionFindings({ timeline, cues, srtText: srtText(cues) }),
    [],
  );
});

test("a word out of order or outside its scene is named", () => {
  const bad = structuredClone(timeline);
  bad.scenes[0].words[1] = { text: "two", start: 0.4, end: 0.4 };
  bad.scenes[0].words[2] = { text: "three", start: 1, end: 2.1 };
  assert.deepEqual(
    captionFindings({ timeline: bad, cues, srtText: srtText(cues) }),
    [
      'word 2 "two" of hook does not start before it ends',
      'word 2 "two" of hook starts before the word before it ends',
      'word 3 "three" of hook falls outside its scene',
    ],
  );
});

test("an empty, overlong, overlapping or overrunning cue is named", () => {
  const long = "x".repeat(CUE_CHARS + 1);
  const bad = [
    { start: 0, end: 0, text: " " },
    { start: 0.5, end: 1, text: long },
    { start: 0.9, end: 2.5, text: "three" },
  ];
  assert.deepEqual(
    captionFindings({ timeline, cues: bad, srtText: srtText(bad) }),
    [
      "cue 1 is empty",
      `cue 2 holds ${CUE_CHARS + 1} characters, over ${CUE_CHARS}`,
      "cue 3 starts before cue 2 ends",
      "cue 3 runs past the video's 2 s",
    ],
  );
});

test("an SRT that is not the cues' copy is named, cue by cue", () => {
  const srt = srtText([
    { start: 0, end: 1, text: "One too" },
    { start: 1.1, end: 1.8, text: "three" },
  ]);
  assert.deepEqual(captionFindings({ timeline, cues, srtText: srt }), [
    'SRT cue 1 reads "One too", the composition "One two"',
    "SRT cue 2 runs 1.1-1.8 s, the composition 1-1.8 s",
  ]);
  assert.deepEqual(
    captionFindings({ timeline, cues, srtText: srtText(cues.slice(1)) }),
    ["the SRT holds 1 cue(s), the composition 2"],
  );
});

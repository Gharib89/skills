// The message at() throws in timing.js for a word its scene lacks, and the
// pattern the gates stage reads it back with. The prefix is defined once; the
// rest of the message is written in timing.mjs's template and matched here,
// and timing.test.mjs pins the thrown text against NO_WORD_RE so rewording
// either cannot turn the anchors gate green. NO_WORD_RE captures the word and
// the scene.
export const NO_WORD = "at: no word";
export const NO_WORD_RE = new RegExp(
  `${NO_WORD} "(.*?)" \\(\\d+\\) in scene (\\S+)`,
);

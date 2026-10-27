// The message at() throws in timing.js for a word its scene lacks, and the
// pattern the gates stage reads it back with: one definition, so rewording the
// message cannot turn the anchors gate green. NO_WORD_RE captures the word and
// the scene.
export const NO_WORD = "at: no word";
export const NO_WORD_RE = new RegExp(
  `${NO_WORD} "(.*?)" \\(\\d+\\) in scene (\\S+)`,
);

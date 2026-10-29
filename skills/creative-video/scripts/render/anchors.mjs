// The messages at() throws in timing.js, for a word its scene lacks and for a
// word its scene repeats with no nth, and the patterns the gates stage reads
// them back with. Each prefix is defined once; the rest of each message is
// written in project.mjs's template and matched here, and timing.test.mjs pins
// the thrown text against each pattern so rewording either side cannot turn
// the anchors gate green. NO_WORD_RE captures the word and the scene;
// REPEATED_WORD_RE the word, the scene and the occurrences' times.
export const NO_WORD = "at: no word";
export const NO_WORD_RE = new RegExp(
  `${NO_WORD} "(.*?)" \\(\\d+\\) in scene (\\S+)`,
);
export const REPEATED_WORD = "at: repeated word, name its nth:";
export const REPEATED_WORD_RE = new RegExp(
  `${REPEATED_WORD} "(.*?)" in scene (\\S+) at (\\d+\\.\\d\\d s(?:, \\d+\\.\\d\\d s)+)`,
);

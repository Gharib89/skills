// The brief's length, shared by the voice stage, the board and the render: the render
// holds the last scene's frame HOLD seconds after its narration, and the
// scenes with that hold land within 10 percent of the brief's `length`.
export const HOLD = 1;

// A chapter of a video in chapters runs 2 to 6 minutes within 10 percent: the
// seconds it may take, the closing hold included on the last one.
export const CHAPTER_SECONDS = [108, 396];

// Whole seconds as m:ss, the way the board and the render's estimate print them.
export function mmss(seconds) {
  const s = Math.round(seconds);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

// Whether `seconds` of scenes and the hold fit a brief `length` of `minutes`.
export function fitsLength(seconds, minutes) {
  const want = minutes * 60;
  return Math.abs(seconds + HOLD - want) <= want * 0.1;
}

// The sentences a narrator voices, each spending its `pause`: Kokoro's adapter
// packs these whole into its calls, a sentence ending where a full stop, ! or ?
// meets a space, not at a script's numbered items, so three items with no full
// stop are one sentence and one item of three sentences is three. Arabic
// narration also ends a sentence at ؟.
export function sentences(text) {
  return text.split(/(?<=[.!?؟])\s+/);
}

// A narration's spoken characters, the unit a narrator's rate is in: its
// letters and digits in any script, not its spaces or punctuation. Kokoro and
// Gemini speak a near-constant number a second whatever the words' length,
// where words a second fall as words lengthen (#783).
export function chars(text) {
  return text.match(/[\p{L}\p{N}]/gu)?.length ?? 0;
}

// The brief's length, shared by the script's budget, the voice stage and the
// render: the render holds the last scene's frame HOLD seconds after its
// narration, and the scenes with that hold land within 10 percent of the
// brief's `length`.
export const HOLD = 1;

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

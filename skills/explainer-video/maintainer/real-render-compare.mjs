// Maintainer only: how real-render.mjs's determinism row reads two more renders
// against the first.

// For each of `others`, the frame hashes against `a`'s: `at`, the indexes of
// `a`'s frames the other render lacks or draws differently, and `n`, those plus
// the frames it has beyond `a`'s last.
export const differing = (a, others) =>
  others.map((b) => {
    const at = a.flatMap((l, i) => (l !== b[i] ? [i] : []));
    return { n: at.length + Math.max(0, b.length - a.length), at };
  });

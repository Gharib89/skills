// The checks a component's props share at compile, each throwing the reason:
// a prop's type, a list of cued items, a cue's sentence and phrase, and the
// props a component takes. lib/visuals.mjs and lib/diagram.mjs check with them.
//
// A cue is `at`, a sentence number, and optionally `on`, a phrase that
// sentence says: the reveal lands on the phrase's first spoken word.

export const words = (s) => s.split(/\s+/).filter(Boolean);
// A word compared without its case or its punctuation, an apostrophe inside
// it included.
const bare = (w) => w.toLowerCase().replace(/[^\p{L}\p{N}\p{M}]+/gu, "");

// Where in the spoken `sentence` the words of `phrase` first run, as a word
// index, or -1.
export function findPhrase(sentence, phrase) {
  const have = words(sentence).map(bare);
  const want = words(phrase).map(bare);
  // A word of bare punctuation would match a bare dash in the sentence.
  if (want.includes("")) return -1;
  for (let i = 0; i + want.length <= have.length; i++)
    if (want.every((w, j) => w === have[i + j])) return i;
  return -1;
}

export const fail = (why) => {
  throw new Error(why);
};
export const object = (x, what) => {
  if (x === null || typeof x !== "object" || Array.isArray(x))
    fail(`${what} is not a JSON object`);
};
export const text = (name, v, what) => {
  if (typeof v !== "string") fail(`${name} needs ${what}`);
};
export const named = (name, v, what) => {
  text(name, v, what);
  if (!v.trim()) fail(`${name} needs ${what}`);
};
// A list prop of `min` to `max` objects, each with a cue.
export function list(name, v, what, said, [min, max] = [1, Infinity]) {
  if (!Array.isArray(v) || v.length < min || v.length > max)
    fail(
      max === Infinity
        ? `${name} needs ${what}`
        : `${name} needs ${min} to ${max} ${what}`,
    );
  for (const x of v) {
    object(x, `a ${name} ${what.replace(/s$/, "")}`);
    cue(x, said);
  }
}
function at(x, n) {
  if (!Number.isInteger(x) || x < 1 || x > n)
    fail(`at ${x} is not a sentence (1 to ${n})`);
}
// `said` holds the scene's sentences in spoken form.
export function cue(x, said) {
  at(x.at, said.length);
  if (x.on === undefined) return;
  if (typeof x.on !== "string" || !words(x.on).length)
    fail("on needs the words of the sentence");
  if (findPhrase(said[x.at - 1], x.on) < 0)
    fail(`on "${x.on}" is not said in sentence ${x.at}`);
}
// Where a cue falls in the scene's speech, as a number that orders cues:
// its sentence, then the phrase's word within it.
export const place = (x, said) =>
  x.at * 1000 + (x.on === undefined ? 0 : findPhrase(said[x.at - 1], x.on));
export const CUE = ["at", "on"];
// A prop the component does not take is refused, never silently dropped;
// `retired` names where one it once took went.
export function known(what, x, allowed, retired = {}) {
  for (const k of Object.keys(x))
    if (!allowed.includes(k))
      fail(
        retired[k]
          ? `${what} has no prop ${k}: ${retired[k]}`
          : `${what} has no prop ${k} (${allowed.join(", ")})`,
      );
}

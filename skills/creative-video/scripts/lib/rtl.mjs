// Right to left text: the Arabic and Latin tests captions and the gates share,
// and the reading rules the layout gate holds an Arabic run's text to, carried
// from explainer-video's layout verdict (lib/layout.mjs there).

export const ARABIC_SCRIPT = /\p{Script=Arabic}/u;

// An Arabic letter: Arabic-Indic digits are in the script but are no letter.
export const ARABIC_LETTER = /(?=\p{Script=Arabic})\p{L}/u;

// Latin letters and no Arabic ones.
export const isLatin = (text) =>
  /[A-Za-z]/.test(text) && !ARABIC_SCRIPT.test(text);

// A Latin run: Latin words, digits among them, joined by single spaces, ending
// on a letter, a digit, `#` or `+` (so `C++` and `C#` hold together and a
// sentence's full stop stays outside).
const RUN =
  /[A-Za-z0-9](?:[A-Za-z0-9#+._/-]*(?: [A-Za-z0-9#+._/-]+)*[A-Za-z0-9#+])?/;

// The text cut around its Latin runs: the runs at odd indexes.
export const splitLatin = (text) => text.split(new RegExp(`(${RUN.source})`));

const ISOLATED = ["isolate", "isolate-override", "plaintext"];

// One text element of the probe at a sample, held to the reading rules, each
// broken rule handed to `bad(what)`. Arabic text reads right to left with no
// Latin run left in it; a Latin run in Arabic text is isolated and on one line,
// so a term keeps its word order; and Arabic text's line height is at least the
// ink its letters span in its face and weight. Text in a box marked
// `dir="ltr"` is exempt: a code frame or a terminal reads left to right as
// written, whatever script it holds.
export function rtlFindings(e, bad) {
  if (e.within === "ltr") return;
  if (ARABIC_SCRIPT.test(e.text)) {
    // Arabic-Indic digits alone have no strong direction, so their isolated
    // `<bdi>` computes `ltr`, which is how a number reads in Arabic text, and
    // they span less than the letters' ink: only a letter is held to either.
    const letters = ARABIC_LETTER.test(e.text);
    if (letters && e.dir !== "rtl") bad(`Arabic reads ${e.dir}`);
    if (/[A-Za-z]/.test(e.text)) bad("Latin run not isolated in");
    if (letters && e.lineH !== null && e.lineH < e.ink)
      bad(`line height ${e.lineH} under the ink ${e.ink} of ${e.face}`);
  } else if (e.within === "rtl" && isLatin(e.text)) {
    if (!ISOLATED.includes(e.bidi)) bad("Latin run not isolated");
    if (e.wrap !== "nowrap") bad("Latin run wraps");
  }
}

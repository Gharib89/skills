// Arabic text as the Egyptian aligner and voice QC read it (#703): no
// diacritics, and English terms spelled in Arabic letters as an Egyptian
// speaker says them, since the model hears and writes nothing else.

// Tashkeel U+064B to U+0652, the dagger alef U+0670, and tatweel U+0640.
export const clean = (s) => s.normalize("NFKC").replace(/[ً-ْٰـ]/g, "");

// For comparisons only: the alef forms, alef maqsura and ta marbuta each read
// as one letter, since speakers and the model write them either way.
export const fold = (s) =>
  clean(s).replace(/[أإآ]/g, "ا").replace(/ى/g, "ي").replace(/ة/g, "ه");

// An acronym's letters by name, A to Z, in the Arabic letters Egyptian
// speakers say them in (P is بي, like B).
const LETTER =
  "ايه بي سي دي اي اف جي اتش اي جاي كاي ال ام ان او بي كيو ار اس تي يو في دبليو اكس واي زد".split(
    " ",
  );

// The rule table from #703's alignment research (tuned on 20 terms), plus
// ssu, said sh (issue): applied in this order as global replaces, so a digraph
// goes before its letters.
const EN2AR = [
  ["ssu", "شو"],
  ["tch", "تش"],
  ["sh", "ش"],
  ["ch", "تش"],
  ["th", "ث"],
  ["ph", "ف"],
  ["ck", "ك"],
  ["qu", "كو"],
  ["ce", "سي"],
  ["ci", "سي"],
  ["c", "ك"],
  ["g", "ج"],
  ["j", "ج"],
  ["k", "ك"],
  ["q", "ك"],
  ["x", "كس"],
  ["p", "ب"],
  ["v", "ف"],
  ["w", "و"],
  ["y", "ي"],
  ["z", "ز"],
  ["b", "ب"],
  ["d", "د"],
  ["f", "ف"],
  ["h", "ه"],
  ["l", "ل"],
  ["m", "م"],
  ["n", "ن"],
  ["r", "ر"],
  ["s", "س"],
  ["t", "ت"],
  ["a", "ا"],
  ["e", "ي"],
  ["i", "ي"],
  ["o", "و"],
  ["u", "و"],
];

// One word with its Latin letters spelled in Arabic: an Arabic prefix (a
// clitic such as ال) is kept; an acronym of 2 to 4 capitals, plural or not
// (PRs), reads as its letters' names; any other word goes through the rule
// table, a doubled letter in the result said once.
export function toArabic(word) {
  const w = clean(word);
  const latin = w.replace(/[^A-Za-z]/g, "");
  if (!latin) return w;
  const prefix = w.replace(/[^ء-يڨی]/g, "");
  const acronym = latin.match(/^([A-Z]{2,4})(s?)$/);
  if (acronym)
    return (
      prefix +
      [...acronym[1]].map((c) => LETTER[c.charCodeAt(0) - 65]).join(" ") +
      (acronym[2] ? "ز" : "")
    );
  let spelt = latin.toLowerCase().replace(/e$/, "");
  for (const [a, b] of EN2AR) spelt = spelt.replaceAll(a, b);
  return prefix + spelt.replace(/(.)\1+/g, "$1");
}

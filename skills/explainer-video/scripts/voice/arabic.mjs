// Arabic text as the Egyptian aligner and voice QC read it (#703): no
// diacritics, and English terms spelled in Arabic letters as an Egyptian
// speaker says them, since the model hears and writes nothing else.

// Tashkeel U+064B to U+0652, the dagger alef U+0670, and tatweel U+0640.
export const clean = (s) => s.normalize("NFKC").replace(/[ً-ْٰـ]/g, "");

// For comparisons only: the alef forms, alef maqsura and ta marbuta each read
// as one letter, since speakers and the model write them either way.
export const fold = (s) =>
  clean(s).replace(/[أإآ]/g, "ا").replace(/ى/g, "ي").replace(/ة/g, "ه");

// An acronym's letters by name, A to Z, as Egyptian speakers say them (P is
// "bi"), then spelled by the rule table like any other word.
const LETTER =
  "ei bi si di i ef ji eitsh ay jei kei el em en o bi kyu ar es ti yu fi dablyu eks way zed".split(
    " ",
  );

// The spec's rule table, from the alignment research (tuned on 20 terms):
// applied in this order as global replaces, so a digraph goes before its
// letters.
const EN2AR = [
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
// clitic such as ال) is kept, an acronym of 2 to 4 capitals reads as its
// letters' names, and a doubled letter in the result is said once.
export function toArabic(word) {
  const w = clean(word);
  let lat = w.replace(/[^A-Za-z]/g, "");
  if (!lat) return w;
  lat = /^[A-Z]{2,4}$/.test(lat)
    ? [...lat].map((c) => LETTER[c.charCodeAt(0) - 65]).join(" ")
    : lat.toLowerCase().replace(/e$/, "");
  for (const [a, b] of EN2AR) lat = lat.replaceAll(a, b);
  const prefix = w.replace(/[^ء-يڨی]/g, "");
  return prefix + lat.replace(/(.)\1+/g, "$1");
}

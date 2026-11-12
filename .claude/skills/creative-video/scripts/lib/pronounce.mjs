// The spoken-form pass: the text a narrator is sent for a word the script
// writes as it is typed, an acronym or a command name (`aws s3 ls`), which a
// TTS model reads as a word ("oos"). A written word's spoken form is the run's
// project/kit/pronounce.json entry for it, else DEFAULTS; matching ignores case
// and the punctuation around a word, and the punctuation is kept. English
// narration only: another language's QC already respells English terms
// (voice/arabic.mjs), and a spelling of Latin letters is no Arabic voice's.
import { maybeJson } from "./json.mjs";

export const PRONOUNCE = "project/kit/pronounce.json";

// Common acronyms and command names a model says as a word or misreads.
export const DEFAULTS = {
  api: "A P I",
  apis: "A P Is",
  aws: "A W S",
  cd: "C D",
  ci: "C I",
  cli: "C L I",
  cpu: "C P U",
  css: "C S S",
  dns: "D N S",
  gcp: "G C P",
  gpu: "G P U",
  html: "H T M L",
  http: "H T T P",
  https: "H T T P S",
  iam: "I A M",
  ide: "I D E",
  npm: "N P M",
  pr: "P R",
  sdk: "S D K",
  sql: "S Q L",
  ssh: "S S H",
  ssl: "S S L",
  sso: "S S O",
  tls: "T L S",
  ui: "U I",
  url: "U R L",
  urls: "U R Ls",
  ux: "U X",
  vpc: "V P C",
};

// `say(word)`: a whitespace-delimited written word as it is sent to the
// narrator, one or more words, or the word itself. Throws what the project's
// map holds wrong.
export function wordSpeaker(run, language) {
  if (language !== "en") return (word) => word;
  const own = maybeJson(run, PRONOUNCE) ?? {};
  for (const key of Object.keys(own))
    if (/\s/.test(key))
      throw new Error(`${PRONOUNCE}: "${key}" is more than one word`);
  const spoken = new Map(Object.entries({ ...DEFAULTS, ...lower(own) }));
  return (word) => {
    const [, before, core, after] = word.match(
      /^([^\p{L}\p{N}]*)(.*?)([^\p{L}\p{N}]*)$/su,
    );
    const said = spoken.get(core.toLowerCase());
    return said === undefined ? word : `${before}${said}${after}`;
  };
}

// `text` with each written word said by `wordSpeaker`'s `say`, its whitespace
// kept.
export const spokenForm = (run, language) => {
  const say = wordSpeaker(run, language);
  return (text) => text.replace(/\S+/g, say);
};

const lower = (map) =>
  Object.fromEntries(Object.entries(map).map(([k, v]) => [k.toLowerCase(), v]));

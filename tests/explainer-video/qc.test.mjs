// Voice QC on Arabic, called directly: the narration against a transcript the
// Egyptian aligner would read, where English terms come back in Arabic letters.
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { fileURLToPath } from "node:url";

const voiceDir = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
  "skills",
  "explainer-video",
  "scripts",
  "voice",
);
const { check } = await import(path.join(voiceDir, "qc.mjs"));
const { toArabic } = await import(path.join(voiceDir, "arabic.mjs"));

const NARRATION =
  "بعد كده الوكيل بيفتح pull request جديد على branch منفصل، وبيستنى المراجعة من الفريق.";
// What the model hears: the same words, English terms spelled as an Egyptian
// speaker says them, no punctuation.
const HEARD =
  "بعد كده الوكيل بيفتح بول ريكويست جديد على برانش منفصل وبيستنى المراجعة من الفريق";
const seconds = (text, rate) => text.length / rate;

test("an Arabic transcript with the English terms spoken in Arabic letters passes", () => {
  const q = check(NARRATION, HEARD, seconds(NARRATION, 13), "ar");
  assert.deepEqual(q.failures, []);
  assert.equal(q.recall, 1);
  assert.equal(q.precision, 1);
  assert.equal(q.rate, 13);
});

// A live Gemini render (#703's live run): the model writes a tatweel clitic
// glued to its English term, and a term in its own spelling, so `الـ pull
// request` comes back as one word and `الـ merge` as المرج.
test("a live Arabic render whose clitics glue to their English terms passes", () => {
  const narration =
    "أهلا بيك. النهارده هنشوف إزاي الـ pull request بيوصل لحد الـ merge.";
  const heard = "اهلا بيك النهاردة هنشوف ازاي البلركوست بيوصل لحد المرج";
  const q = check(narration, heard, seconds(narration, 13), "ar");
  assert.deepEqual(q.failures, []);
  assert.equal(q.recall, 1);
  assert.equal(q.precision, 1);
});

test("a cut Arabic transcript fails recall at 0.8", () => {
  const cut = HEARD.split(" ").slice(0, 6).join(" ");
  const q = check(NARRATION, cut, seconds(NARRATION, 13), "ar");
  assert.ok(q.recall < 0.8, String(q.recall));
  assert.match(q.failures.join("; "), /^recall [\d.]+ under 0\.8$/);
});

test("a looped Arabic transcript fails precision at 0.85", () => {
  const q = check(NARRATION, `${HEARD} ${HEARD}`, seconds(NARRATION, 13), "ar");
  assert.equal(q.recall, 1);
  assert.equal(q.precision, 0.5);
  assert.deepEqual(q.failures, ["precision 0.5 under 0.85"]);
});

test("an Arabic rate outside 9 to 22 chars/s fails", () => {
  for (const rate of [5, 30]) {
    const q = check(NARRATION, HEARD, seconds(NARRATION, rate), "ar");
    assert.deepEqual(q.failures, [`rate ${rate} chars/s outside 9 to 22`]);
  }
});

test("an English term matches its Arabic spelling only through transliteration", () => {
  assert.equal(toArabic("request"), "ريكويست");
  assert.equal(toArabic("pull"), "بول");
  assert.equal(toArabic("CI"), "سي اي");
  // An acronym's letters by their Arabic names, A included, plural or not.
  assert.equal(toArabic("AI"), "ايه اي");
  assert.equal(toArabic("API"), "ايه بي اي");
  assert.equal(toArabic("PRs"), "بي ارز");
  const terms = "pull request review branch git CI";
  const heard = "بول ريكويست ريفيو برانش جيت سي اي";
  assert.deepEqual(check(terms, heard, seconds(terms, 13), "ar").failures, []);
  // Compared raw, as the English path does, no term is found.
  assert.match(
    check(terms, heard, seconds(terms, 13), "en").failures.join("; "),
    /^recall 0 under 0\.8/,
  );
});

test("issue said as ايشو passes, its ssu heard as sh", () => {
  assert.equal(toArabic("issue"), "يشو");
  const q = check("issue", "ايشو", seconds("issue", 13), "ar");
  assert.deepEqual(q.failures, []);
});

test("an acronym of function words or vowel letters still counts", () => {
  for (const [acronym, said] of [
    ["AI", "ايه اي"],
    ["UI", "يو اي"],
    ["IO", "اي او"],
  ]) {
    const narration = `ده ${acronym}`;
    const heard = `ده ${said}`;
    assert.deepEqual(
      check(narration, heard, seconds(narration, 13), "ar").failures,
      [],
      acronym,
    );
    assert.match(
      check(narration, "ده", seconds(narration, 13), "ar").failures.join("; "),
      /^recall 0 under 0\.8$/,
      acronym,
    );
  }
});

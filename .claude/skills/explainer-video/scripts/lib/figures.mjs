// The numbers a scene shows: what counts as a number written in digits, whether
// a text holds one whole, and every one a list of texts writes. lib/visuals.mjs
// checks a chart's or a stat's values with them, and the script gate finds a
// shown number in a cited excerpt with `numberIn`.

import { plain } from "./count.mjs";
import { fail } from "./props.mjs";

// A number as a source writes it: digits, thousands commas that group by
// three, an optional decimal part. Its characters are what the script gate
// finds in an excerpt, and what a count-up ends on.
// It is written in ASCII, Arabic-Indic (١٢٠٠) or Persian (۱۲۰۰) digits, one
// script to a number, as an Arabic source writes it.
const NUMBER = /^(0|[1-9]\d*|[1-9]\d{0,2}(,\d{3})+)(\.\d+)?$/;
const SCRIPTS = [/[0-9]/, /[٠-٩]/, /[۰-۹]/];
export function digits(name, v) {
  if (v === undefined) fail(`${name} needs a value per item`);
  if (
    typeof v !== "string" ||
    !NUMBER.test(plain(v)) ||
    SCRIPTS.filter((s) => s.test(v)).length > 1
  )
    fail(
      `${name} value ${JSON.stringify(v)} is not a number written in digits (1200 or 1,200.5)`,
    );
  // What a double keeps exactly: a longer one would count up and size a bar
  // from a rounded (or infinite) number.
  if (plain(v).replace(/\D/g, "").length > 15)
    fail(`${name} value ${JSON.stringify(v)} has more than 15 digits`);
}
const DIGIT = "[0-9\\u0660-\\u0669\\u06f0-\\u06f9]";
const POINT = "[.,\\u066b\\u066c]";
// Whether `value` stands in `text` as written and whole, never as part of a
// longer number (200 is not in 1,200 nor 5 in 0.5), in any digit script.
export const numberIn = (text, value) =>
  new RegExp(
    `(?<!${DIGIT})(?<!${DIGIT}${POINT})${value.replace(/\./g, "\\.")}(?!${DIGIT})(?!${POINT}${DIGIT})`,
  ).test(text);
// Every number written in `texts` as `numberIn` reads one: digits joined by a
// point or comma between digits, so `Q3 '21` holds 3 and 21.
export const numbersIn = (texts) =>
  texts.flatMap(
    (t) => t?.match(new RegExp(`${DIGIT}+(?:${POINT}${DIGIT}+)*`, "g")) ?? [],
  );

// The narrators a script and setup name: narrators.json's list.
import fs from "node:fs";
import path from "node:path";
import { parseJson } from "./json.mjs";
import { skill } from "./tools.mjs";

// narrators.json holds each narrator's own fields over its backend's `defaults`
// block (language, style, licence, leavesMachine, a null rate and pause, not a
// default), the voice being the id unless the entry names one. The narrators
// of `body`, narrators.json's text, as every reader sees them: the entry's
// fields over the defaults, held to the file's shape. A body that is not
// JSON, or not that shape, is left for `parseJson` to refuse.
export function parseNarrators(body) {
  let doc;
  try {
    doc = JSON.parse(body);
  } catch {
    return parseJson("narrators.json", body).narrators;
  }
  if (Array.isArray(doc?.narrators))
    doc.narrators = doc.narrators.map((n) => ({
      voice: n?.id,
      ...doc.defaults?.[n?.backend],
      ...n,
    }));
  return parseJson("narrators.json", JSON.stringify(doc)).narrators;
}

export const narrators = () =>
  parseNarrators(fs.readFileSync(path.join(skill, "narrators.json"), "utf8"));

// The narrator `id` names for `language`, or the language's first default when
// id is undefined; null when none.
export function narrator(id, language) {
  return (
    narrators().find(
      (n) => n.language === language && (id ? n.id === id : n.default),
    ) ?? null
  );
}

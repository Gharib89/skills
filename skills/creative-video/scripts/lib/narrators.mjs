// The narrators a script and setup name: narrators.json's list.
import fs from "node:fs";
import path from "node:path";
import { parseJson } from "./json.mjs";
import { skill } from "./tools.mjs";

export const narrators = () =>
  parseJson(
    "narrators.json",
    fs.readFileSync(path.join(skill, "narrators.json"), "utf8"),
  ).narrators;

// The narrator `id` names for `language`, or the language's first default when
// id is undefined; null when none.
export function narrator(id, language) {
  return (
    narrators().find(
      (n) => n.language === language && (id ? n.id === id : n.default),
    ) ?? null
  );
}

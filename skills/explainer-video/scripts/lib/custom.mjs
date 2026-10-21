// The `custom` component's checks at compile: its props, its declared cues and
// the fragment its `file` names, read through `ctx.read` (compile reads beside
// the scene file). Compile keeps the fragment's text as `source` in script.json,
// so a later stage plays what was linted. lib/fragment.mjs holds the lint.
import { lintFragment } from "./fragment.mjs";
import { CUE, cue, fail, known, named, object } from "./props.mjs";

// A file name beside the scene file: relative, never up out of its folder.
const BESIDE = /^(?![\\/])(?!.*(?:^|[\\/])\.\.(?:[\\/]|$))[^:\0]+\.html?$/i;

// The names of a scene's declared cues, each checked as a cue.
function cueNames(cues, said) {
  if (cues === undefined) return [];
  if (!Array.isArray(cues)) fail("custom cues needs a list of cues");
  const names = [];
  for (const c of cues) {
    object(c, "a custom cue");
    named("a custom cue", c.name, "a name");
    if (!/^[A-Za-z][\w-]*$/.test(c.name))
      fail(
        `custom cue name "${c.name}" is not a plain name (letters, digits, dashes)`,
      );
    if (names.includes(c.name)) fail(`custom cue ${c.name} is named twice`);
    cue(c, said);
    known("a custom cue", c, ["name", ...CUE]);
    names.push(c.name);
  }
  return names;
}

export function checkCustom(p, said, ctx = {}) {
  if (typeof p.file !== "string" || !BESIDE.test(p.file))
    fail("custom file needs a file beside the scene file (an .html path)");
  named(
    "custom intent",
    p.intent,
    "an intent, one line of what the scene shows",
  );
  if (/[\r\n]/.test(p.intent.trim())) fail("custom intent is one line");
  const names = cueNames(p.cues, said);
  let src;
  try {
    src = ctx.read(p.file);
  } catch (e) {
    fail(
      e.code === "ENOENT"
        ? `custom file ${p.file} is not beside the scene file`
        : `custom file ${p.file} cannot be read: ${e.message}`,
    );
  }
  try {
    lintFragment(src, { names, arabic: ctx.language === "ar" });
  } catch (e) {
    fail(`custom file ${p.file}: ${e.message}`);
  }
}

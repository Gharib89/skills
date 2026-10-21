// The `custom` component: the agent's own fragment (props.source, kept at
// compile) as the scene's markup, its plain rules and its script. The composer
// scopes the rules a line at a time and adds the script to the scene's paused
// timeline; the cues the scene declares reach the script by name.
import { splitFragment, splitSelectors } from "../lib/fragment.mjs";

// A rule's selector list as one rule per selector, since the composer scopes
// the start of a line: `.a, .b { x }` is `.a { x }` and `.b { x }`.
function perSelector(rule) {
  const open = rule.indexOf("{");
  const body = rule.slice(open);
  return splitSelectors(rule.slice(0, open)).map((s) => `${s} ${body}`);
}

export const custom = (p) => {
  const { markup, css, script } = splitFragment(p.source);
  return {
    html: markup,
    css: css.flatMap(perSelector).join("\n"),
    reveals: [],
    fragment: { script, cues: p.cues ?? [] },
  };
};

// The `browser` component's props at compile, and the page geometry the
// composer draws them in: the scene file holds no coordinates, and the cursor's
// path is computed from the same boxes the page is drawn with.
import {
  CUE,
  fail,
  known,
  list,
  named,
  object,
  place,
  text,
} from "./props.mjs";

// "a, b or c", for a refusal naming what is allowed.
const oneOf = (xs) => `${xs.slice(0, -1).join(", ")} or ${xs.at(-1)}`;

// The elements a generic page draws, each at a fixed height: a heading, a line
// of text, a button, a text field and a link.
export const KINDS = { heading: 88, text: 64, button: 72, field: 72, link: 56 };
const ACTS = ["move", "click", "type"];

// The page, in px. The window is as tall as the content band under the `bands`
// layout (compose.mjs's CONTENT, the shorter of the two) and the elements stand
// in a column under its bar, at the reading start.
export const PAGE = { width: 1360, height: 690, bar: 72, pad: 40, gap: 24 };
export const COLUMN = { width: 880, inset: 120 };

// A frame holds a page by height, not by count: the elements' heights and the
// gaps between them must fit in `room`.
const room = PAGE.height - PAGE.bar - 2 * PAGE.pad;
const stacked = (elements) =>
  elements.reduce((h, e) => h + KINDS[e.kind], 0) +
  (elements.length - 1) * PAGE.gap;

// Throws the first reason the props `p` are not a browser page for the scene's
// sentences in spoken form, `said`.
export function checkBrowser(p, said) {
  named("browser", p.url, "a url");
  named("browser", p.title, "a title");
  if (!Array.isArray(p.elements) || !p.elements.length)
    fail("browser needs elements");
  for (const e of p.elements) object(e, "a browser element");
  const ids = p.elements.map((e) => e.id);
  for (const e of p.elements) {
    named("browser", e.id, "an id per element");
    if (ids.indexOf(e.id) !== ids.lastIndexOf(e.id))
      fail(`browser element id "${e.id}" is used twice`);
    if (!Object.hasOwn(KINDS, e.kind))
      fail(
        `browser element kind "${e.kind}" is not ${oneOf(Object.keys(KINDS))}`,
      );
    named("browser", e.text, "a text per element");
    known("a browser element", e, ["id", "kind", "text"]);
  }
  if (stacked(p.elements) > room)
    fail(
      `browser lays out ${p.elements.length} elements; a frame holds ${fits(p.elements)} of this height`,
    );
  list("browser", p.actions, "actions", said);
  let last;
  for (const [i, a] of p.actions.entries()) {
    const target = p.elements[ids.indexOf(a.target)];
    if (!target)
      fail(
        `browser action target ${JSON.stringify(a.target)} names no element (${ids.join(", ")})`,
      );
    if (!ACTS.includes(a.act))
      fail(`browser action act ${JSON.stringify(a.act)} is not ${oneOf(ACTS)}`);
    if (a.act === "type") {
      if (a.text === undefined) fail("browser type action needs text");
      named("browser", a.text, "text to type");
      if (target.kind !== "field")
        fail(
          `browser type action targets "${a.target}", a ${target.kind}; type needs a field`,
        );
    } else if (a.text !== undefined) {
      fail(`browser ${a.act} action takes no text`);
    }
    // One cursor runs the page, so two actions never share a moment.
    if (last && place(a, said) <= place(last, said))
      fail(`browser action ${i + 1} cues at or before action ${i}`);
    last = a;
    known("a browser action", a, [...CUE, "target", "act", "text"]);
  }
}

// How many of the first elements' heights a frame holds, for the refusal.
function fits(elements) {
  let n = 0;
  while (n < elements.length && stacked(elements.slice(0, n + 1)) <= room) n++;
  return n;
}

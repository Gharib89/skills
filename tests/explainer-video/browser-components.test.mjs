// The `browser` component at compile: a generic page of elements and scripted
// actions (a cursor moving, a click, typed text), each action naming the
// element it acts on by id. An id no element holds is refused. It is rich (it
// draws its own frame), so a `camera` key is refused on it.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  VISUALS,
  checkVisual,
} from "../../skills/explainer-video/scripts/lib/visuals.mjs";

const said = [
  "Open the sign-up page.",
  "Type the name into the field.",
  "Then press the button.",
];
const browser = (props) => ({
  component: "browser",
  props: {
    url: "example.com/signup",
    title: "Sign up",
    elements: [
      { id: "head", kind: "heading", text: "Create an account" },
      { id: "name", kind: "field", text: "Your name" },
      { id: "go", kind: "button", text: "Continue" },
    ],
    actions: [
      { at: 1, target: "head", act: "move" },
      { at: 2, target: "name", act: "type", text: "Ada Lovelace" },
      { at: 3, on: "the button", target: "go", act: "click" },
    ],
    ...props,
  },
});
const bad = (visual, why) =>
  assert.throws(() => checkVisual(visual, said), why);

test("a page with a cursor move, typed text and a click compiles", () => {
  assert.doesNotThrow(() => checkVisual(browser(), said));
});

test("an action naming an unknown element id is refused at compile", () => {
  bad(
    browser({ actions: [{ at: 1, target: "email", act: "click" }] }),
    /browser action target "email" names no element \(head, name, go\)/,
  );
});

test("an action takes a known act, and a type act takes text on a field", () => {
  bad(
    browser({ actions: [{ at: 1, target: "go", act: "hover" }] }),
    /browser action act "hover" is not move, click or type/,
  );
  bad(
    browser({ actions: [{ at: 1, target: "name", act: "type" }] }),
    /browser type action needs text/,
  );
  bad(
    browser({ actions: [{ at: 1, target: "go", act: "type", text: "x" }] }),
    /browser type action targets "go", a button; type needs a field/,
  );
  bad(
    browser({ actions: [{ at: 1, target: "go", act: "click", text: "x" }] }),
    /browser click action takes no text/,
  );
});

test("actions cue in order, each on a sentence the scene has", () => {
  bad(
    browser({
      actions: [
        { at: 2, target: "name", act: "move" },
        { at: 1, target: "go", act: "move" },
      ],
    }),
    /browser action 2 cues at or before action 1/,
  );
  bad(
    browser({
      actions: [
        { at: 2, target: "name", act: "move" },
        { at: 2, target: "go", act: "move" },
      ],
    }),
    /browser action 2 cues at or before action 1/,
  );
  bad(
    browser({ actions: [{ at: 9, target: "go", act: "click" }] }),
    /at 9 is not a sentence \(1 to 3\)/,
  );
  bad(
    browser({
      actions: [{ at: 3, on: "the moon", target: "go", act: "click" }],
    }),
    /on "the moon" is not said in sentence 3/,
  );
});

test("a page needs a url, a title, elements with unique ids and kinds it draws, and actions", () => {
  bad(browser({ url: "" }), /browser needs a url/);
  bad(browser({ title: undefined }), /browser needs a title/);
  bad(browser({ elements: [] }), /browser needs elements/);
  bad(browser({ actions: [] }), /browser needs actions/);
  bad(
    browser({
      elements: [
        { id: "a", kind: "heading", text: "A" },
        { id: "a", kind: "text", text: "B" },
      ],
    }),
    /browser element id "a" is used twice/,
  );
  bad(
    browser({ elements: [{ id: "a", kind: "image", text: "A" }] }),
    /browser element kind "image" is not heading, text, button, field or link/,
  );
  bad(
    browser({ elements: [{ id: "a", kind: "text" }] }),
    /browser needs a text per element/,
  );
});

test("a prop the browser does not take is refused, on the page, an element and an action", () => {
  bad(browser({ theme: "dark" }), /browser has no prop theme/);
  bad(
    browser({ elements: [{ id: "a", kind: "text", text: "A", x: 1 }] }),
    /a browser element has no prop x/,
  );
  bad(
    browser({ actions: [{ at: 1, target: "head", act: "move", y: 1 }] }),
    /a browser action has no prop y/,
  );
});

test("a page taller than the frame holds is refused at compile", () => {
  const rows = (n) =>
    Array.from({ length: n }, (_, i) => ({
      id: `e${i}`,
      kind: "text",
      text: `Line ${i}`,
    }));
  const page = (n) =>
    browser({
      elements: rows(n),
      actions: [{ at: 1, target: "e0", act: "move" }],
    });
  assert.doesNotThrow(() => checkVisual(page(6), said));
  bad(page(9), /browser lays out 9 elements; a frame holds 6 of this height/);
});

test("a browser is rich: it draws its own camera, so a camera key is refused", () => {
  bad(
    { ...browser(), camera: { at: 3 } },
    /browser draws its own camera, so it takes no camera key/,
  );
});

test("every number on the page is a claim the script gate holds to an excerpt", () => {
  const numbers = VISUALS.browser.numbers(
    browser({
      url: "example.com/v2",
      elements: [{ id: "a", kind: "text", text: "Step 3 of 4" }],
      actions: [{ at: 1, target: "a", act: "move" }],
    }).props,
  );
  assert.deepEqual(numbers, ["2", "3", "4"]);
  const typed = VISUALS.browser.numbers(
    browser({
      elements: [{ id: "a", kind: "field", text: "Age" }],
      actions: [{ at: 1, target: "a", act: "type", text: "42" }],
    }).props,
  );
  assert.deepEqual(typed, ["42"]);
});

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  endsLatin,
  keptTerms,
  mapScreen,
  rename,
  respell,
} from "../../skills/explainer-video/scripts/lib/terms.mjs";

test("a respelt kept term changes only where it stands as a whole Latin run", () => {
  // `CI/CD`, `node.js` and `pull request review` are kept terms of their own.
  assert.equal(
    rename("الـ CI و CI/CD", new Map([["CI", "GitHub Actions"]])),
    "الـ GitHub Actions و CI/CD",
  );
  assert.equal(
    rename("نشغل node.js و node", new Map([["node", "Node"]])),
    "نشغل node.js و Node",
  );
  assert.equal(
    rename(
      "نعمل pull request review و review",
      new Map([["review", "code review"]]),
    ),
    "نعمل pull request review و code review",
  );
  assert.equal(
    rename("وpull request،", new Map([["pull request", "PR"]])),
    "وPR،",
  );
});

test("a token ends in a Latin word whatever Arabic prefix it carries, and not on punctuation, digits or Arabic", () => {
  assert.ok(endsLatin("pull"));
  assert.ok(endsLatin("وpull"));
  assert.ok(endsLatin("C++"));
  assert.ok(!endsLatin("request،"));
  assert.ok(!endsLatin("pull."));
  assert.ok(!endsLatin("و2024"));
  assert.ok(!endsLatin("بيوصل"));
});

test("a Latin term used only in the video's title is kept", () => {
  const script = {
    title: "إزاي Ship بيوصل لـ GitHub",
    scenes: [
      {
        captions: [[{ text: "Ship" }, { text: "بيشتغل" }]],
        visual: { component: "title", props: { title: "Ship" } },
      },
    ],
  };
  assert.deepEqual(keptTerms(script), ["Ship", "GitHub"]);
});

test("an excerpt's quoted pack text is no kept term and no rewrite reaches it", () => {
  const visual = {
    component: "excerpt",
    props: {
      cite: "ex-1",
      emphasis: { target: "We open a pull request.", at: 1 },
      excerpts: {
        "ex-1": {
          text: "We open a pull request.",
          locator: "src/cache.js:1",
          code: false,
        },
      },
    },
  };
  const script = {
    title: "عنوان",
    scenes: [{ captions: [[{ text: "بيشتغل" }]], visual }],
  };
  assert.deepEqual(keptTerms(script), []);
  assert.equal(
    mapScreen(visual, (s) => s.toUpperCase()),
    visual,
  );
});

test("a respelt term drops the spoken form of a brace it covers, even one holding part of it", () => {
  const spellings = new Map([
    ["pull request", "PR"],
    ["CI", "GitHub Actions"],
  ]);
  assert.equal(
    respell("نفتح {pull|بول} request و {AI|ايه اي}", spellings),
    "نفتح PR و {AI|ايه اي}",
  );
  assert.equal(
    respell("الـ {CI|سي آي} بيشغل", spellings),
    "الـ GitHub Actions بيشغل",
  );
});

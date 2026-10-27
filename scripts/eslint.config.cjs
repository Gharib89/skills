// The `no-undef` hook's config (.pre-commit-config.yaml): a call to a name a
// file never imports or declares, and nothing else. Prek's own hook
// environment holds eslint, globals and espree and sets NODE_PATH to it, so
// this file is CommonJS: an ESM `import "globals"` does not resolve there.
const fs = require("node:fs");
const espree = require("espree");
const globals = require("globals");

// A classic page script shares one scope with the scripts loaded before it, so
// a boot file may call what its core file declares at top level. Add a page
// here when it gets a core and boot pair.
const pages = [
  "skills/explainer-video/storyboard/card",
  "skills/explainer-video/storyboard/page",
  "skills/grill-with-artifact/page",
];
// A page that split its core file: the parts load after the core, the core
// calls what they declare, and each calls what the core and the others declare.
const parts = {
  "skills/explainer-video/storyboard/page": ["sections", "summary"],
};

// The names a classic script declares at top level, read from the file itself
// so a function removed from a core file leaves its boot file's call undefined.
function declaredNames(file) {
  const names = {};
  const ast = espree.parse(fs.readFileSync(file, "utf8"), {
    ecmaVersion: "latest",
  });
  for (const node of ast.body) {
    if (node.id) names[node.id.name] = "readonly";
    for (const d of node.declarations ?? []) names[d.id.name] = "readonly";
  }
  return names;
}

const rules = { "no-undef": "error" };

module.exports = [
  {
    files: ["**/*.mjs"],
    languageOptions: {
      sourceType: "module",
      // nodeBuiltin, not node: node adds require, module and __dirname, which
      // an ES module does not have, so a call to one would pass and throw.
      globals: { ...globals.nodeBuiltin },
    },
    rules,
  },
  // The modules whose page.evaluate bodies run in a page. Browser globals
  // elsewhere would let a missing import of a helper named open, close, find
  // or name pass, since the browser declares those too.
  {
    files: [
      "skills/explainer-video/scripts/lib/backend/browser.mjs",
      "skills/explainer-video/scripts/lib/backend/source.mjs",
      "skills/creative-video/scripts/lib/backend/source.mjs",
    ],
    languageOptions: { globals: globals.browser },
  },
  {
    files: ["**/*.js"],
    languageOptions: { sourceType: "script", globals: globals.browser },
    rules,
  },
  ...pages.flatMap((page) => {
    const scripts = [
      `${page}-core.js`,
      ...(parts[page] ?? []).map((part) => `${page}-${part}.js`),
    ];
    const names = (files) => Object.assign({}, ...files.map(declaredNames));
    return [
      {
        files: [`${page}-boot.js`],
        languageOptions: { globals: names(scripts) },
      },
      ...(scripts.length > 1
        ? scripts.map((file) => ({
            files: [file],
            languageOptions: {
              globals: names(scripts.filter((other) => other !== file)),
            },
          }))
        : []),
    ];
  }),
];

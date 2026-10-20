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
      globals: { ...globals.nodeBuiltin, ...globals.browser },
    },
    rules,
  },
  {
    files: ["**/*.js"],
    languageOptions: { sourceType: "script", globals: globals.browser },
    rules,
  },
  ...pages.map((page) => ({
    files: [`${page}-boot.js`],
    languageOptions: { globals: declaredNames(`${page}-core.js`) },
  })),
];

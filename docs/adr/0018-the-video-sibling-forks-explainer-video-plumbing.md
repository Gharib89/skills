# The video sibling forks explainer-video's plumbing

The sibling skill that makes freely authored narrated videos copies the grammar-free plumbing it needs from `explainer-video` into its own folder and keeps no link back: no script called by sibling path, no shared library skill. Only the voice stage takes grammar-free input today (`render.mjs`, `gates.mjs` and `layout.mjs` import the component grammar), so a runtime dependency would reuse voice and setup alone at the price of three cross-skill contracts (installed together, the run-folder schema, a version pin) and would stop `explainer-video` from ever being retired. A shared library would mean refactoring `explainer-video`, which the effort that chose this ruled out of scope.

## Consequences

- The copy is a second owner of the same code: a fix in one copy does not reach the other. No check ties them; the fork's PR names its base commit, so a later fix ports by `git diff <base>` over the forked paths.
- The sibling keeps its own config, data and tool cache under its own name (ADR 0017's layout, a second set of directories): models download again and an own voice is enrolled again with its consent.
- The copy can grow past its source: the sibling's own voice narrates English as well as Egyptian Arabic, which `explainer-video`'s does not.

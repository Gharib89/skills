# explainer-video installs its tools into a per-user cache

`explainer-video` ships only `package.json` and its lockfile; setup runs `npm ci` into a per-user tool cache keyed by the lockfile's hash, and downloads Chrome and models there too, never into the skill's own folder. `npx skills add` copies a skill once per scope, and in this repo `.claude/skills/` is a derived copy the `derived-copies` gate diffs, so about 1.3 GB of `node_modules`, Chrome and models inside the skill would repeat in every copy and break the gate. Keying by the lock hash lets a project-scoped and a user-scoped copy at different versions coexist, and a version bump reinstalls cleanly.

## Considered Options

- `node_modules` inside each installed skill copy: no cache to locate, but one install per copy and a dirty derived copy here.
- Per project, under `explainers/.tools/`: one install per repo that makes videos.

## Consequences

- ADR 0014 gains a third per-user directory, cache, under `explainer-video/`: `$XDG_CACHE_HOME` or `~/.cache` on Linux, `~/Library/Caches` on macOS, `%LOCALAPPDATA%` on Windows. It holds `node/<lock-hash>/`, Chrome and `models/`.
- Models the skill exports itself (the Egyptian Arabic aligner, later the English one) are hosted in a Hugging Face model repo under the owner's account, pinned by commit and checked by sha256, the same route `kokoro-js` downloads Kokoro by.
- Stage caches (voice, stills, renders, scene gates, 3D clips) are not tools: they live in the run folder, `explainers/<slug>/.cache/`, and go with the run.

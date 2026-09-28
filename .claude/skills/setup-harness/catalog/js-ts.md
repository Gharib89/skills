# JS/TS

## Signals
Kind: stack
Manifest: package.json
Lockfile: pnpm-lock.yaml, package-lock.json, yarn.lock, bun.lock
Workspace: pnpm-workspace.yaml, package.json `workspaces`
Extensions: .ts .tsx .js .jsx .mjs .cjs .mts .cts
Shebangs: node
Runtime version: .nvmrc, .node-version, package.json `engines`, .tool-versions, mise.toml

## lint

### ESLint
Publisher: OpenJS
Tier: 2: https://github.com/eslint/eslint
Evidence: `eslint.config.*`, `.eslintrc*`, `eslint` dev dependency
Rung: edit
Run: `eslint --fix {files}`
Hook: https://github.com/eslint/eslint
Pin: package npm eslint
Route: `npm install -g eslint@{version}`; Blocked: None.
Constraints: ESLint 9 and later lint nothing without a flat config; a default writes `eslint.config.mjs` extending `@eslint/js` and, for TypeScript, `typescript-eslint`, both exact dev dependencies through the install check.
Traps: the vendor hook runs in an isolated env; flat-config plugins must be listed under `additional_dependencies` or they are not resolvable.

### Biome
Publisher: biomejs
Tier: 2: https://github.com/biomejs/biome
Evidence: `biome.json`, `biome.jsonc`, `@biomejs/biome` dev dependency
Rung: edit
Run: `biome lint --write {files}`
Hook: https://github.com/biomejs/pre-commit
Pin: package npm @biomejs/biome
Route: `npm install -g @biomejs/biome@{version}`; Blocked: None.
Constraints: None.
Traps: None.

### oxlint
Publisher: oxc-project
Tier: 2: https://github.com/oxc-project/oxc
Evidence: `.oxlintrc.json`, `oxlint` dev dependency
Rung: edit
Run: `oxlint --fix --deny-warnings {files}`
Hook: https://github.com/oxc-project/mirrors-oxlint
Pin: package npm oxlint
Route: `npm install -g oxlint@{version}`; Blocked: None.
Constraints: None.
Traps: every finding is a warning by default and exits 0; `--deny-warnings` is required for it to gate anything.

## format

### Prettier
Publisher: Prettier
Tier: 2: https://github.com/prettier/prettier
Evidence: `.prettierrc*`, `prettier.config.*`, `prettier` dev dependency
Rung: edit
Run: `prettier --write {files}`
Hook: local
Pin: package npm prettier
Route: `npm install -g prettier@{version}`; Blocked: None.
Constraints: None.
Traps: `prettier/pre-commit` and `pre-commit/mirrors-prettier` are both archived; do not wire either.

### Biome format
Publisher: biomejs
Tier: 2: https://github.com/biomejs/biome
Evidence: `biome.json`, `biome.jsonc`, `@biomejs/biome` dev dependency
Rung: edit
Run: `biome format --write {files}`
Hook: https://github.com/biomejs/pre-commit
Pin: package npm @biomejs/biome
Route: `npm install -g @biomejs/biome@{version}`; Blocked: None.
Constraints: None.
Traps: None.

## typecheck

### tsc
Publisher: Microsoft
Tier: 2: https://github.com/microsoft/TypeScript
Evidence: `tsconfig.json`, `typescript` dev dependency
Rung: turn
Run: `tsc --noEmit`
Hook: local
Pin: package npm typescript
Route: `npm install -g typescript@{version}`; Blocked: None.
Constraints: typescript-eslint requires `typescript >=4.8.4 <6.1.0`.
Traps: `tsc --noEmit <file>` fails with `TS5112` once a tsconfig is present; run project-scoped only, with no file arguments.

## test runner

### Vitest
Publisher: vitest-dev
Tier: 2: https://github.com/vitest-dev/vitest
Evidence: `vitest.config.*`, `vite.config.*` with a `test` key, `vitest` dev dependency
Rung: turn
Run: `vitest run`
Hook: local
Pin: package npm vitest
Route: `npm install -g vitest@{version}`; Blocked: None.
Constraints: None.
Traps: None.

### Jest
Publisher: jestjs
Tier: 2: https://github.com/jestjs/jest
Evidence: `jest.config.*`, `jest` key in `package.json`, `jest` dev dependency
Rung: turn
Run: `jest`
Hook: local
Pin: package npm jest
Route: `npm install -g jest@{version}`; Blocked: None.
Constraints: None.
Traps: `--watchman` defaults true; pass `--no-watchman` where the binary is absent.

### node:test
Publisher: nodejs
Tier: 2: https://nodejs.org/api/test.html
Evidence: `node:test` imports in test files, no dedicated config file
Rung: turn
Run: `node --test`
Hook: local
Pin: None.
Route: None.
Constraints: ships with the stack's own pinned Node runtime; no separate package to install.
Traps: no changed-files or related-tests mode; only whole-suite or watch mode.

## affected tests

### Vitest related
Publisher: vitest-dev
Tier: 2: https://github.com/vitest-dev/vitest
Evidence: `vitest.config.*`, `vite.config.*` with a `test` key, `vitest` dev dependency
Rung: turn
Run: `vitest related --run {files}`
Hook: local
Pin: package npm vitest
Route: `npm install -g vitest@{version}`; Blocked: None.
Constraints: follows static imports only; a dynamic `import()` is not tracked.
Traps: None.

### Jest findRelatedTests
Publisher: jestjs
Tier: 2: https://github.com/jestjs/jest
Evidence: `jest.config.*`, `jest` key in `package.json`, `jest` dev dependency
Rung: turn
Run: `jest --findRelatedTests {files}`
Hook: local
Pin: package npm jest
Route: `npm install -g jest@{version}`; Blocked: None.
Constraints: None.
Traps: None.

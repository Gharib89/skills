// A house Markdown scene file with one scene per component, shared by the
// compile and render tests.
export const SCRIPT = `# How Ship lands a pull request
language: en
narrator: am_fenrir
style: claude-code

## Scene hook · The promise
target: about fifteen seconds

### Narration
1. Ship drives {#626|issue six two six} to a \`merged\` pull request. [ex-3, ex-4]
2. Here is how. [no-claim]

### Visual
\`\`\`json
{ "component": "title", "props": { "kicker": "Ship", "title": "Issue to pull request", "subtitle": "One run, one merge" } }
\`\`\`

## Scene steps · The steps

### Narration
1. It reads the issue. [ex-1]
2. It writes a failing test. [ex-2]
3. Then the code makes it pass. [ex-5]

### Visual
\`\`\`json
{
  "component": "cards",
  "props": {
    "items": [
      { "at": 1, "label": "Input", "value": "issue" },
      { "at": 2, "label": "First", "value": "test", "note": "failing" },
      { "at": 3, "label": "Then", "value": "code" }
    ]
  }
}
\`\`\`

## Scene gate · The gate

### Narration
1. The local gate runs every check. [ex-6]
2. Then it opens the pull request. [ex-7]

### Visual
\`\`\`json
{ "component": "terminal", "props": { "title": "scripts/local-gate.sh", "lines": [ { "at": 1, "text": "$ scripts/local-gate.sh" }, { "at": 2, "text": "gh pr create" } ] } }
\`\`\`
`;

// One scene per diagram and code component, for the render tests.
export const DIAGRAMS = `# How Ship lands a pull request
language: en
narrator: am_fenrir
style: claude-code

## Scene flow · The flow

### Narration
1. It reads the issue. [ex-1]
2. It writes a failing test. [ex-2]
3. Then the code makes it pass. [ex-5]

### Visual
\`\`\`json
{ "component": "flow", "props": { "steps": [ { "at": 1, "label": "Issue" }, { "at": 2, "label": "Test", "note": "red" }, { "at": 3, "label": "Code", "note": "green" } ] } }
\`\`\`

## Scene sides · The two sides

### Narration
1. The worktree holds the change. [ex-1]
2. The main checkout stays clean. [ex-2]

### Visual
\`\`\`json
{ "component": "panels", "props": { "items": [ { "at": 1, "title": "Worktree", "body": "The branch and every edit" }, { "at": 2, "title": "Main", "body": "Untouched until the merge" } ] } }
\`\`\`

## Scene gates · The gates

### Narration
1. The gate lints. [ex-6]
2. It runs the tests. [ex-6]

### Visual
\`\`\`json
{ "component": "list", "props": { "title": "The local gate", "items": [ { "at": 1, "text": "Lint every script" }, { "at": 2, "text": "Run every test" } ] } }
\`\`\`

## Scene code · The code

### Narration
1. The script starts strict. [ex-6]
2. Then it runs the gate. [ex-6]

### Visual
\`\`\`json
{ "component": "code", "props": { "lang": "bash", "file": "scripts/gate.sh", "code": "set -euo pipefail\\nscripts/check.sh full", "emphasis": { "target": [2, 2], "at": 2 } } }
\`\`\`

## Scene diff · The fix

### Narration
1. The test failed. [ex-2]
2. The fix changes one line. [ex-5]

### Visual
\`\`\`json
{ "component": "codediff", "props": { "lang": "js", "file": "src/sum.js", "before": "export function sum(a, b) {\\n  return a - b;\\n}", "after": "export function sum(a, b) {\\n  return a + b;\\n}", "at": 2 } }
\`\`\`
`;

// One stack3d scene, which draws WebGL, for the GPU render tests.
export const STACK3D = `# How Ship lands a pull request
language: en
narrator: am_fenrir
style: claude-code

## Scene stack · The stack

### Narration
1. The issue is the base. [ex-1]
2. A failing test sits on it. [ex-2]
3. Then the code makes it pass. [ex-5]

### Visual
\`\`\`json
{ "component": "stack3d", "props": { "layers": [ { "at": 1, "label": "Issue" }, { "at": 2, "label": "Test" }, { "at": 3, "label": "Code" } ] } }
\`\`\`
`;

// An Egyptian Arabic scene file, written in Arabic with its kept terms in
// Latin letters: a title, a flow and a code frame, for the Arabic tests.
export const ARABIC = `# إزاي Ship بيوصل لحد pull request
language: ar
narrator: ar-eg-csagent-2
style: claude-code

## Scene hook · الوعد

### Narration
1. Ship بياخد issue واحدة ويوصلها لحد pull request متراجع. [ex-1]
2. خلينا نشوف إزاي. [no-claim]

### Visual
\`\`\`json
{ "component": "title", "props": { "kicker": "Ship", "title": "من issue لحد pull request", "subtitle": "تشغيلة واحدة و merge واحد" } }
\`\`\`

## Scene steps · الخطوات

### Narration
1. الأول بيعمل branch جديد. [ex-2]
2. بعدين بيشغل الـ CI على الـ branch. [ex-3]
3. وفي الآخر بيطلب review قبل الـ merge. [ex-4]

### Visual
\`\`\`json
{ "component": "flow", "props": { "steps": [ { "at": 1, "label": "branch", "note": "جديد" }, { "at": 2, "label": "CI" }, { "at": 3, "label": "review", "note": "قبل الـ merge" } ] } }
\`\`\`

## Scene code · الأمر

### Narration
1. الـ CI بيشغل الأمر ده على كل pull request. [ex-5]

### Visual
\`\`\`json
{ "component": "code", "props": { "lang": "sh", "file": "local-gate.sh", "code": "scripts/local-gate.sh\\ngh pr create" } }
\`\`\`
`;

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

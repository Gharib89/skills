<!-- ccr-overview-v2 -->

## Copilot review overview

### 🟡 Changes recommended

Compare pagination is unspecified, so ranges exceeding 30 commits can still omit subjects.

**Review effort:** Balanced
**Findings:** 2 <picture><source media="(prefers-color-scheme: dark)" srcset="https://github.githubassets.com/static/images/icons/copilot-code-review/medium-v2-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://github.githubassets.com/static/images/icons/copilot-code-review/medium-v2-light.svg"><img src="https://github.githubassets.com/static/images/icons/copilot-code-review/medium-v2-light.png" alt="Medium severity" width="62" height="18" align="texttop"></picture>

<details open>
<summary><strong>Open (2)</strong></summary>

- <picture><source media="(prefers-color-scheme: dark)" srcset="https://github.githubassets.com/static/images/icons/copilot-code-review/medium-v2-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://github.githubassets.com/static/images/icons/copilot-code-review/medium-v2-light.svg"><img src="https://github.githubassets.com/static/images/icons/copilot-code-review/medium-v2-light.png" alt="Medium severity" width="62" height="18" align="texttop"></picture> [Follow pagination when fetching compare commits](#discussion_r4178133335) · New
- <picture><source media="(prefers-color-scheme: dark)" srcset="https://github.githubassets.com/static/images/icons/copilot-code-review/medium-v2-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://github.githubassets.com/static/images/icons/copilot-code-review/medium-v2-light.svg"><img src="https://github.githubassets.com/static/images/icons/copilot-code-review/medium-v2-light.png" alt="Medium severity" width="62" height="18" align="texttop"></picture> [Follow pagination when fetching compare commits](#discussion_r4178133362) · New
</details>

<details>
<summary><strong>What changed in this PR</strong></summary>

Updates `update-skills` to identify upstream subjects by commit ancestry rather than dates.

**Changes:**
- Intersects path-filtered commits with compare-range commits.
- Refreshes the derived skill copy and lock hash.

### Standards
Source and derived copies remain synchronized.

### Spec
The ancestry approach addresses #469, but missing pagination leaves larger ranges incomplete.

| File | Description |
| ---- | ----------- |
| `skills/​update-skills/​SKILL.md` | Defines ancestry-based subject selection. |
| `.claude/​skills/​update-skills/​SKILL.md` | Refreshes the installed skill copy. |
| `skills-lock.json` | Updates the computed skill hash. |
</details>

---

💡 <a href="/Gharib89/skills/new/main?filename=.github/skills/code-review/SKILL.md" class="Link--inTextBlock" target="_blank" rel="noopener noreferrer">Add a `code-review` agent skill</a> or configure MCP servers for context-aware, tailored reviews. <a href="https://docs.github.com/copilot/how-tos/use-copilot-agents/request-a-code-review/use-code-review?tool=webui#mcp-servers-and-agent-skills" class="Link--inTextBlock" target="_blank" rel="noopener noreferrer">Learn more in the docs.</a>

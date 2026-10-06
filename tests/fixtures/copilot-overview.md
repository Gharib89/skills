<!-- ccr-overview-v2 -->

## Copilot review overview

### 🔵 Needs a closer look

Empty or whitespace-only locks still allow installation without skill selectors, installing every upstream skill.

**Review effort:** Balanced  
**Findings:** None

<details>
<summary><strong>Resolved since last review (1)</strong></summary>

- <picture><source media="(prefers-color-scheme: dark)" srcset="https://github.githubassets.com/static/images/icons/copilot-code-review/high-v2-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://github.githubassets.com/static/images/icons/copilot-code-review/high-v2-light.svg"><img src="https://github.githubassets.com/static/images/icons/copilot-code-review/high-v2-light.png" alt="High severity" width="62" height="18" align="texttop"></picture> [Shell command injection via unescaped lock keys in eval](#discussion_r4178245107)
</details>

<details>
<summary><strong>Previously missed (1)</strong></summary>

In code that hasn't changed since last review

<details>
<summary><picture><source media="(prefers-color-scheme: dark)" srcset="https://github.githubassets.com/static/images/icons/copilot-code-review/medium-v2-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://github.githubassets.com/static/images/icons/copilot-code-review/medium-v2-light.svg"><img src="https://github.githubassets.com/static/images/icons/copilot-code-review/medium-v2-light.png" alt="Medium severity" width="62" height="18" align="texttop"></picture> Empty skills lock bypasses guard and installs all skills</summary>

`skills/​update-skills/​SKILL.md:50`

An empty or whitespace-only `skills-lock.json` still bypasses the guard: `jq -r` exits 0 without output, leaving `flags` empty. The installer then runs without any `--skill` selectors and installs every source-repo skill. Unlike the malformed JSON covered by the new test, this input does not fail parsing. Use `jq -er` here and in `skills/setup-skills/ship-block.md` to reject input that produces no result, refresh both derived copies, and add empty and whitespace-only lock cases to the regression test.
</details>
</details>

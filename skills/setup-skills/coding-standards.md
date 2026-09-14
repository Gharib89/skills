# Coding standards

The standards every change in this repo is reviewed against. The `code-review` skill's Standards axis and every automated reviewer read this file; the ship profile names it under `## Coding standards`.

<!-- setup-skills: record what already exists and is enforced today. True on the day it is written; extend as standards are decided. Never move prose out of CLAUDE.md; link to it. -->

## Enforced by tooling

<!-- One line per config-enforced tool, naming the config that enforces it: "ruff, per pyproject.toml [tool.ruff]"; "mypy --strict, per mypy.ini"; "prettier, per .prettierrc". -->

## Written standards

<!-- Links to the sections of CLAUDE.md / AGENTS.md or contributing docs that carry inline standards, one line each with what the section covers. -->

## Conventions a reviewer should know

<!-- The entries below are ship's, true in every repo that installs it; leave them and add the repo's own conventions under them: commit subject format, test naming, layering rules. `None recorded yet.` is a legal line for the repo's own conventions. -->

- **PR body: the Summary opens with a Shape.** A `diff` fence over a call tree, file tree, control flow, pseudocode or component tree, first thing under `## Summary`, or first in the body where no template gives that heading. Text forms only, never mermaid and never HTML. One shape, about 15 lines or fewer. Every node is a real symbol, each tree's root node carries its file path, and no line carries a line number. A change that moves no logic and no layout opens with `Shape: none, mechanical (<kind>).` instead; silent absence is a finding.
- **A vocabulary the change extends is swept across the whole tree, sibling spellings included.** Grep the new term and the ones it sits beside, across every file rather than the ones the diff already opened; a stale spelling left in the copy nobody grepped reads as the current rule to the agent that finds it first.
- **A rule-shaped prose change reaches every item it governs, one outcome each.** Enumerate the items the rule names and check the change lands on each exactly once; an item the rewrite skipped, or one left carrying two answers, is where a reviewer finds five rounds of work.
- **New pattern-matching code is tested against adversarial inputs.** Delimiters inside the field, option groups, field-versus-line anchoring, and the path where the tooling itself fails; ten lines of regex read as correct and answer wrong on the input nobody wrote a case for.
- **A fix landed after review has its hunk re-read before the push.** Read the changed lines back out of the file, not out of the reply you are about to post; a fix applied to the wrong copy or applied by half costs a whole round to discover.

# Coding standards

The standards every change in this repo is reviewed against. The `code-review` skill's Standards axis and every automated reviewer read this file; the ship profile names it under `## Coding standards`.

<!-- setup-skills: record what already exists and is enforced today. True on the day it is written; extend as standards are decided. Never move prose out of CLAUDE.md; link to it. -->

## Enforced by tooling

<!-- One line per config-enforced tool, naming the config that enforces it: "ruff, per pyproject.toml [tool.ruff]"; "mypy --strict, per mypy.ini"; "prettier, per .prettierrc". -->

## Written standards

<!-- Links to the sections of CLAUDE.md / AGENTS.md or contributing docs that carry inline standards, one line each with what the section covers. -->

## Conventions a reviewer should know

<!-- The PR body entry below is ship's, true in every repo that installs it; leave it and add the repo's own conventions under it: commit subject format, test naming, layering rules. `None recorded yet.` is a legal line for the repo's own conventions. -->

- **PR body: the Summary opens with a Shape.** A `diff` fence over a call tree, file tree, control flow, pseudocode or component tree, first thing under `## Summary`, or first in the body where no template gives that heading. Text forms only, never mermaid and never HTML. One shape, about 15 lines or fewer. Every node is a real symbol, each tree's root node carries its file path, and no line carries a line number. A change that moves no logic and no layout opens with `Shape: none, mechanical (<kind>).` instead; silent absence is a finding.

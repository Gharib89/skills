# Coding standards

The standards every change in this repo is reviewed against. The `code-review` skill's Standards axis and every automated reviewer read this file; the ship profile names it under `## Coding standards`.

This repo ships bash and Markdown. Every file in it is read by an agent, so prose is the product as much as the scripts are.

## Enforced by tooling

- `shellcheck -x -s bash -P SCRIPTDIR -S warning` over every tracked script under `skills/`, `scripts/` and `tests/`, per the `shellcheck` gate in `scripts/local-gate.sh`. Warnings fail; suppress one only with a `# shellcheck disable=<code>` carrying the reason on the same line, and only where the warning actually fires.
- `gitleaks detect` over the branch's commits, per the `secrets` gate in the same file.
- `.claude/skills/<name>/` byte-identical to `skills/<name>/` for `ship`, `cloud-ship` and `setup-skills`, per the `derived-copies` gate.
- No em dashes in any file this repo authors, per the `house-style` gate.
- The mechanics' malformed-invocation contract, per the `contract` gate: no `${N:?}` expansion under `skills/ship/scripts/`, and every mechanic that requires an argument, invoked with none, prints exactly one JSON object with an `error` key and exits 2. The check reaches no host, because every usage guard fires before the adapter loads; a mechanic whose guard fires later breaks that and fails the gate.
- `tests/run.sh` green, per the `tests` gate. It runs every `tests/*.test.sh`: the pure transformations the mechanics are built around, sourced and asserted on as strings, reaching no host. A behavioural claim about one of them earns a case there.

## Written standards

- [CONTEXT.md](../../CONTEXT.md) is the glossary. Use its terms in prose, issue titles and commit subjects, and avoid the synonyms each entry lists.
- [docs/adr/](../adr/) records decisions. Contradicting one is surfaced, not done silently.
- The `writing-for-agents` skill governs every document here: context pointers, the information hierarchy, leading words, pruning.
- [docs/agents/ship.md](../agents/ship.md) `## Public surface` enumerates what a consumer repo depends on. A change to any of it is a breaking change for repos that have already installed a derived copy.

## Conventions a reviewer should know

- **The source is `skills/`, never `.claude/skills/`.** The derived copies are install output. A change lands in `skills/<name>/` and reaches `.claude/skills/` only through `npx skills add . --skill <name> --agent claude-code -y`.
- **Mechanics print JSON and nothing else on stdout.** Evidence goes to stderr, capped at the last 40 lines. Exit 0 success, 1 the operation failed, 2 tooling.
- **No host CLI outside a named mechanic.** `gh` and `az` are called only from `skills/ship/scripts/host/<host>.sh`; a host operation no mechanic performs is a ship defect, not a prose fallback.
- **Commit subjects** are conventional-commit prefixed and scoped to the skill: `fix(ship):`, `docs:`, `feat(setup-skills):`.
- **`.claude/skills/` is exempt from every rule here.** It is install output from other people's repos and is never edited in place, so its prose and its em dashes are not this repo's to fix.
- **Every `mktemp` is paired with a trap.** `trap 'rm -f "$f"' EXIT` at script top level, `trap 'rm -f "$f"' RETURN` for a file created inside a function. An interrupted run between the `mktemp` and the `rm -f` otherwise leaves the file in the system temp directory.
- **Commit messages** carry no em dashes either. The `house-style` gate reads files, not messages, so this one is on the author.

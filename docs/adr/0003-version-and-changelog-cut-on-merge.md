---
status: accepted
---

# The release run on main cuts the version bump and the changelog

Every change to a skill had to bump that skill's `metadata.version` in the same PR. The number is one line in one file, so any two PRs touching the same skill collided on it, and a run that merged its base in had to re-grade its own bump against the new number. The retro tickets #218, #219 and #220 were chained for that reason alone. The grade already sat in the PR title, which `ship` writes as a Conventional Commit and `merge.sh` passes as the squash `commit_title`.

So the release moves to main. `.github/workflows/semantic-release.yml` runs python-semantic-release once per skill on every push to main, reading the Conventional-Commit type of the squash subject: every type is at least a patch, because a derived copy changes whatever the type says and a consumer compares the number before refreshing; `feat` is minor; a `!` or a `BREAKING CHANGE:` footer is major. A PR leaves the version line alone, which the `version-lines` gate holds it to, so nothing serialises on it.

Two guards sit around the grade. `bump-guard` refuses a PR title that is not a Conventional Commit of a type the release run reads, and one implying a major bump without the maintainer's `major` label, so a major bump is never an agent's decision alone; this inherits the rule from the `crm` repo's ADR 0011, whose `minor`-label gate was already retired there for stalling agent PRs, and which is why `feat` needs no label here either. The second guard is `merge.sh` passing the PR title as `commit_title`: the subject `bump-guard` validated is the subject the release run reads, whatever the host's own squash-title setting says.

## Considered options

- **Keep the bump in the PR.** Rejected: it is the collision, and every workaround (rebase, re-grade, chain the tickets) costs a run's wall time.
- **Use python-semantic-release's own GitHub Action with a `config_file` input**, which the issue proposed. Rejected on inspection: the action runs in a `python:3.14-slim-trixie` container carrying no node, and each configuration's build command runs `npx skills add` to refresh the derived copy. The CLI on the runner, pinned to the same version, reaches node and does the same work.
- **Parse the squash body for further conventional commits** (`parse_squash_commits = true`), which the issue also proposed, so the body's `BREAKING CHANGE:` footer would be read. Rejected: the footer is read either way, and with squash parsing on a PR body that quotes a conventional-commit example reads as a second commit. A local run graded a `docs(ship):` commit minor because its body listed `- feat(ship): add a flag`, which this repo's bodies routinely do.
- **One configuration for the whole repo.** Rejected: three skills version independently, and a consumer refreshing one reads only that skill's number.

## Consequences

- Each skill needs a baseline tag at the version it already carries, pushed once before the workflow first fires:

  ```sh
  git tag ship-v7.0.0 origin/main && git tag cloud-ship-v1.0.2 origin/main \
    && git tag setup-skills-v4.0.1 origin/main && git push origin --tags
  ```

  Without a tag matching its `tag_format`, python-semantic-release ignores the number in `SKILL.md` and forces `1.0.0`, which would regress `ship` from 7.x; the workflow's first step refuses to release rather than cut that version, so a forgotten tag costs a red run and not a wrong release.
- `metadata.profile-schema` stays a hand edit. The `## Schema N` entry it carries is written by the change that needs it, and no subject can derive that entry.
- Each skill's changelog lives at `skills/<name>/CHANGELOG.md`, inside the skill directory rather than at the repo root, because the derived copy mirrors the whole directory: the changelog reaches a consumer with the skill it describes, so the version a consumer reads and the entries explaining it arrive together. `prose-budget` reads only `SKILL.md` and `reference/*.md`, and `stray-files` already admits everything under `skills/`, so neither gate needed changing.
- The release commit runs the repo's refresh line as its build command, so `.claude/skills/` and `skills-lock.json` move with the bump and `derived-copies` stays green on main.
- The release run pushes with the default `GITHUB_TOKEN`, whose pushes start no workflow run, so it cannot recurse; the job's `if` on a `chore(release):` head commit is the second guard. Main's ruleset must admit that push.

Decided in Gharib89/skills#222.

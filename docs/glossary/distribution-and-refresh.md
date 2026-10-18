### Distribution and Refresh

**Composed skill**:
A skill Ship takes a phase's logic from at the phase that needs it, rather than reimplementing it: `tdd`, `writing-for-agents`, `code-review`, `find-docs` and `show-me`. Ship loads each through the Skill tool, except `show-me`, which it reads as a file because its upstream disables model invocation. A skill a composed skill calls through the Skill tool is composed too, since only a composed skill is installed beside it: `codebase-design`, which `tdd` calls. Ship's `metadata.composes` line names each with the repo and pinned ref it installs from, and preflight refuses a run before the claim when one is absent from the consumer repo's `.claude/skills/`, or its `skills-lock.json` records it at another ref. Adding one, or moving its pin, is therefore a breaking change for installed consumers. `setup-skills` composes `triage` the same way, so it counts as one wherever composed skills are pinned and checked. The inverse of a sibling skill: Ship composes these, a sibling composes Ship.
_Avoid_: dependency, sub-skill, helper skill

**Derived copy**:
The copy of a shared skill committed under a repo's `.claude/skills/`, installed from this repo and left as installed, every change going to the source. A repo's copy is what runs, in the attended and unattended lanes alike, and refreshing it is the repo owner's act. A shared skill is installed at repo scope, because a personal skill silently shadows a repo's; `setup-project` alone installs at user scope, since it runs before a repo has any (ADR 0007).
_Avoid_: vendored fork, sync, symlink, snapshot

**Source repo**:
This repo, `Gharib89/skills`: where the skills recorded with `source: "."` in its lock, `skills-lock.json`, are written, and where the versions of their composed skills are tested. Every derived copy of those skills is installed from it.
_Avoid_: upstream (that is a composed skill's own repo), skills repo, origin

**Consumer repo**:
Any repo holding derived copies installed from the source repo, the source repo included, since it installs its own. A consumer repo owns its per-repo docs and never edits its copies.
_Avoid_: derived repo, client repo, target repo

**Pinned ref**:
The upstream commit of a composed skill that the source repo tested Ship against: the one version of it any consumer repo installs. It moves only when the source repo refreshes that skill on purpose.
_Avoid_: tested version, locked version, hash (the lock's `computedHash` is the folder's content hash, not the ref)

**Upstream drift**:
A composed skill whose upstream has moved past its pinned ref. Reported to the source repo, never acted on in a consumer repo: a consumer that installed the new upstream would run Ship against a version nobody tested. In the source repo the drift issue also lists every other upstream skill whose upstream moved past its lock ref.
_Avoid_: outdated skill, stale dependency

**Refresh**:
Re-installing a consumer repo's derived copies, and its composed skills at their pinned refs, then running Ship's preflight so a profile the new Ship no longer reads is reported at once. The repo owner's act, which `update-skills` performs.
_Avoid_: sync, upgrade, update (the CLI's `update` ignores pinned refs)

**Retired term**:
A word a source-repo skill stops using, declared in that skill's `retired-terms.md` with the version that retired it and the word that replaces it, so a refresh that crosses that version can find the word in the consumer repo's own documents and replace it there, renaming a file whose name is the word.
_Avoid_: deprecated term, old vocabulary, stale wording

**Release run**:
The push-to-main workflow that owns every skill's `metadata.version`: it writes the number and cuts that skill's `CHANGELOG.md`, one run per skill, from the Conventional-Commit type of the squash subject. The `version-lines` gate refuses a PR that writes the line instead. `semantic-release` is the tool that runs it, and the value the ship profile's `Tooling:` line takes.
_Avoid_: release job, auto-bump, version bump PR

# Ship profile: versioning notes

Why the release run owns `metadata.version` and why the PR title is load-bearing. Reference for a title or version question. Vocabulary: [GLOSSARY.md](../../GLOSSARY.md).

**The release run owns `metadata.version`.** `.github/workflows/semantic-release.yml` writes it on every push to main, once per skill, from the commits that touched that skill's `skills/<name>/`: every conventional type is at least a patch, `feat` is minor, and a `!` or a `BREAKING CHANGE:` footer is minor while the skill is 0.x, as every skill is until its public release, and major after ([ADR 0005](../adr/0005-skills-stay-0x-until-public-release.md)). The `version-lines` gate ([ship.md](ship.md#local-gate)) refuses a diff that moves the line, so a hand bump is caught before the PR opens rather than by a reviewer. `metadata.profile-schema` is the exception and stays a hand edit, because the `## Schema N` entry it carries is written by the change that needs it.

The title is therefore load-bearing twice: the `bump-guard` leg holds it to a Conventional Commit of a type the release run reads and gates the major grade behind the maintainer's `major` label, and `merge.sh` passes it as the squash `commit_title` so the subject the leg validated is the subject the release run reads. A human merging through the host's own UI instead must land the PR title as that subject.

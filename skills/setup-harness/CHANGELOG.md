# CHANGELOG

Every entry here is written by the release run on main, which grades the bump
from the squash subject's Conventional-Commit type and cuts one entry per
released version. See
[docs/adr/0003-version-and-changelog-cut-on-merge.md](https://github.com/Gharib89/skills/blob/main/docs/adr/0003-version-and-changelog-cut-on-merge.md).

<!-- version list -->

## v0.6.1 (2026-09-28)

### Bug Fixes

- **setup-harness**: Pass ShellCheck at default severity in the check.sh template
  ([#385](https://github.com/Gharib89/skills/pull/385),
  [`014f6d4`](https://github.com/Gharib89/skills/commit/014f6d454605c7045e32e5535a9afff295dcdea4))


## v0.6.0 (2026-09-28)

### Features

- **setup-harness**: Surfaces and behaviour tools
  ([#382](https://github.com/Gharib89/skills/pull/382),
  [`0a17675`](https://github.com/Gharib89/skills/commit/0a17675dc772413920fc3c10e1a2ce72d650b39d))


## v0.5.1 (2026-09-28)

### Bug Fixes

- **skills**: Keep every skill self-contained, and gate it
  ([#380](https://github.com/Gharib89/skills/pull/380),
  [`76934a4`](https://github.com/Gharib89/skills/commit/76934a4d031a8f63229b3c79ea93df4d762b016e))


## v0.5.0 (2026-09-28)

### Features

- **setup-harness**: Catalog entries for Go, Rust, .NET, Java/Kotlin, Dockerfile, workflows and
  Markdown ([#378](https://github.com/Gharib89/skills/pull/378),
  [`ca2322d`](https://github.com/Gharib89/skills/commit/ca2322d56aaa0321a1dd88de65ba0a1545e89625))


## v0.4.0 (2026-09-28)

### Features

- **setup-harness**: The re-run gap report and the check.sh contract check
  ([#375](https://github.com/Gharib89/skills/pull/375),
  [`4e0de2e`](https://github.com/Gharib89/skills/commit/4e0de2ec72f7f72bafb4230f35a5e564c4db320d))


## v0.3.0 (2026-09-28)

### Features

- **setup-harness**: Vendored language servers and the LSP proof
  ([#374](https://github.com/Gharib89/skills/pull/374),
  [`3b6d33f`](https://github.com/Gharib89/skills/commit/3b6d33fab6e0b24918e570c52d78fca2368c3327))


## v0.2.0 (2026-09-28)

### Features

- **setup-harness**: Cloud setup, the cloud-first verdict and its proof
  ([#372](https://github.com/Gharib89/skills/pull/372),
  [`7324351`](https://github.com/Gharib89/skills/commit/73243511ff3e36977588a9e910c66c0c85d4b2f3))


**The renumber to 0.x.** Every entry below predates it and keeps the number it was released under. `setup-harness` was never publicly released, so on 2026-09-28 its version moved from 1.0.0 to 0.1.0: the old major is now the minor. The release run writes new entries above this note, counting on from 0.1.0. See [ADR 0005](https://github.com/Gharib89/skills/blob/main/docs/adr/0005-skills-stay-0x-until-public-release.md).

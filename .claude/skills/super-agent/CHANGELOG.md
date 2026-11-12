# CHANGELOG

Every entry here is written by the release run on main, which grades the bump
from the squash subject's Conventional-Commit type and cuts one entry per
released version. See
[docs/adr/0003-version-and-changelog-cut-on-merge.md](https://github.com/Gharib89/skills/blob/main/docs/adr/0003-version-and-changelog-cut-on-merge.md).

<!-- version list -->

## v0.20.0 (2026-11-12)

### Features

- **super-agent**: Merge-gate ruler, fixed resume step, notify command and the owner's rulings
  ([#1168](https://github.com/Gharib89/skills/pull/1168),
  [`aa551f5`](https://github.com/Gharib89/skills/commit/aa551f54532f355ebe381d6abe4e164d7e5f209f))


## v0.19.0 (2026-11-12)

### Features

- **super-agent**: Reconcile prints the wake's actions, and fewer wakes
  ([#1167](https://github.com/Gharib89/skills/pull/1167),
  [`836c871`](https://github.com/Gharib89/skills/commit/836c871b8bf72167b30ed823c4cae9a310eab2bb))


## v0.18.0 (2026-11-11)

### Features

- **super-agent**: An ordered waiting list with blockers, and ready rows from reconcile
  ([#1166](https://github.com/Gharib89/skills/pull/1166),
  [`8097dc4`](https://github.com/Gharib89/skills/commit/8097dc45492af9c799d5cc285979934faa3093b6))


## v0.17.0 (2026-11-11)

### Features

- **super-agent**: Watch every launched thread to rest
  ([#1161](https://github.com/Gharib89/skills/pull/1161),
  [`6c42952`](https://github.com/Gharib89/skills/commit/6c4295282194d0a9a26e8212d6379803478bdfaf))


## v0.16.0 (2026-11-11)

### Features

- **super-agent**: One launch script and a record step, a per-repo ship cap and scoped brief lines
  ([#1160](https://github.com/Gharib89/skills/pull/1160),
  [`dbcdbb2`](https://github.com/Gharib89/skills/commit/dbcdbb2de61316128e2ea9c71e90bb3c8763f7c4))


## v0.15.0 (2026-11-11)

### Features

- **super-agent**: Route by weekly weight with a 5 hour floor and a weekly reserve
  ([#1158](https://github.com/Gharib89/skills/pull/1158),
  [`85bf683`](https://github.com/Gharib89/skills/commit/85bf68392bc326c36688bc1f37d0933531f7bb47))


## v0.14.0 (2026-11-11)

### Features

- **super-agent**: Status block printed by a script, silent when nothing changed
  ([#1157](https://github.com/Gharib89/skills/pull/1157),
  [`b1c1cfc`](https://github.com/Gharib89/skills/commit/b1c1cfc14d94068b0df427dbe061267700c1930e))


## v0.13.2 (2026-11-11)

### Bug Fixes

- **super-agent**: Share repo and path normalisers, state the Linux target
  ([#1154](https://github.com/Gharib89/skills/pull/1154),
  [`873efe9`](https://github.com/Gharib89/skills/commit/873efe9cbd928fd49de98897ee0f5ebd9469b1bd))


## v0.13.1 (2026-11-10)

### Bug Fixes

- **super-agent**: Treat a settled ship entry as merged when removing its worktree
  ([#1139](https://github.com/Gharib89/skills/pull/1139),
  [`1e02c06`](https://github.com/Gharib89/skills/commit/1e02c06a021b875d9fe43982a934596b075c3b44))


## v0.13.0 (2026-11-09)

### Features

- **super-agent**: Expire a recorded auth failure instead of keeping it forever
  ([#1135](https://github.com/Gharib89/skills/pull/1135),
  [`093c069`](https://github.com/Gharib89/skills/commit/093c0699ac9b440eb9a167c700ccf2da9386d8a0))


## v0.12.1 (2026-11-09)

### Bug Fixes

- **super-agent**: Claim by comment only, never assign the ticket
  ([#1132](https://github.com/Gharib89/skills/pull/1132),
  [`211b361`](https://github.com/Gharib89/skills/commit/211b361d2f0abb9c68acb73ea2779878cc04b8eb))


## v0.12.0 (2026-11-09)

### Features

- **super-agent**: Keep a grill entry watched past its first rest
  ([#1131](https://github.com/Gharib89/skills/pull/1131),
  [`24c6c06`](https://github.com/Gharib89/skills/commit/24c6c06b7c3639c6dbb8ed73f9131a4f7ec3a629))


## v0.11.0 (2026-11-09)

### Features

- **super-agent**: Route cursor and grok only when allowed or named
  ([#1129](https://github.com/Gharib89/skills/pull/1129),
  [`3aca7cd`](https://github.com/Gharib89/skills/commit/3aca7cd817bcb75d79ea694ec1409a52e9696579))


## v0.10.1 (2026-11-09)

### Bug Fixes

- **super-agent**: Read a cursor instance's auth from its T3 row only
  ([#1122](https://github.com/Gharib89/skills/pull/1122),
  [`c6aed5a`](https://github.com/Gharib89/skills/commit/c6aed5a20936a31158fa4d64801add00e0035d6f))


## v0.10.0 (2026-11-09)

### Features

- **super-agent**: Route cursor and grok instances as a last resort
  ([#1119](https://github.com/Gharib89/skills/pull/1119),
  [`e7d54db`](https://github.com/Gharib89/skills/commit/e7d54db0878f12ec2e676918b98eb1a7f7841d30))


## v0.9.1 (2026-11-08)

### Bug Fixes

- **super-agent**: Read each Claude instance's own account in quota and auth
  ([#1117](https://github.com/Gharib89/skills/pull/1117),
  [`912ae36`](https://github.com/Gharib89/skills/commit/912ae3689e4bb52e5f6a83e50c198505c659a411))


## v0.9.0 (2026-11-08)

### Features

- **super-agent**: Route launches across provider instances, check auth, carry rulings, remove
  settled worktrees ([#1115](https://github.com/Gharib89/skills/pull/1115),
  [`7c8764c`](https://github.com/Gharib89/skills/commit/7c8764c3ee444bb20070a8e7d4265ec1caba1a1f))


## v0.8.1 (2026-11-06)

### Bug Fixes

- **super-agent**: Re-add a finished ticket, work week from the fleet file
  ([#1109](https://github.com/Gharib89/skills/pull/1109),
  [`80b49c7`](https://github.com/Gharib89/skills/commit/80b49c72fc6d7f75fcb0870a4ef620119c8894d7))


## v0.8.0 (2026-11-06)

### Features

- **super-agent**: Watch and reconcile threads on linked machines
  ([#1096](https://github.com/Gharib89/skills/pull/1096),
  [`d425740`](https://github.com/Gharib89/skills/commit/d42574089d52a3ee5f115a7148d5186d4bee99af))


## v0.7.0 (2026-11-06)

### Features

- **super-agent**: Standing waivers, schedules and lessons
  ([#1095](https://github.com/Gharib89/skills/pull/1095),
  [`dfefb70`](https://github.com/Gharib89/skills/commit/dfefb70efdaf7bfaa2f56883d4e57b8637867240))


## v0.6.0 (2026-11-06)

### Features

- **super-agent**: Claims and intake ([#1094](https://github.com/Gharib89/skills/pull/1094),
  [`6e38bf5`](https://github.com/Gharib89/skills/commit/6e38bf54c5fbc653894cc4391e318a9cfc8deddd))


## v0.5.0 (2026-11-06)

### Features

- **super-agent**: Placement across linked machines
  ([#1092](https://github.com/Gharib89/skills/pull/1092),
  [`60f6d35`](https://github.com/Gharib89/skills/commit/60f6d3576c3a2d6c534eb669495b7ca1c945358e))


## v0.4.0 (2026-11-06)

### Features

- **super-agent**: Quota-aware routing and agy jobs
  ([#1091](https://github.com/Gharib89/skills/pull/1091),
  [`ff45ef2`](https://github.com/Gharib89/skills/commit/ff45ef2f1345700378fb145358ed701cd44e6522))


## v0.3.0 (2026-11-06)

### Features

- **super-agent**: Stalls and permission holds
  ([#1090](https://github.com/Gharib89/skills/pull/1090),
  [`8b4c285`](https://github.com/Gharib89/skills/commit/8b4c28536530f94141e6f32b2dafc3dd1932858f))


## v0.2.0 (2026-11-06)

### Features

- **super-agent**: Fleet file and setup script
  ([#1089](https://github.com/Gharib89/skills/pull/1089),
  [`3ff38da`](https://github.com/Gharib89/skills/commit/3ff38da6e3cf373ebc1bed8d2e166c04827b40a7))

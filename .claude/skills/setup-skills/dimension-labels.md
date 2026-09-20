## Dimension labels

<!-- setup-skills: written verbatim into docs/agents/triage-labels.md after the five-role table, this comment removed. The Colour column is what the host step creates each label with. -->

Three orthogonal axes beside the five triage roles. Triage stamps **at most one label per axis**, at triage time, alongside the role label, so a maintainer glancing at the tracker reads off what kind of change an issue is, how big it is and how urgent it is without opening it.

Implementation order is **derived** from priority, size and blocking edges, and is never stored as a label: a rank label rots the moment a higher issue ships.

### Kind

What kind of change the issue asks for, aligned with the Conventional Commit type that grades the release, so the label read at triage is the type the PR title carries.

| Label | Colour | Description |
| --- | --- | --- |
| `bug` | `d73a4a` | Something isn't working |
| `enhancement` | `a2eeef` | New feature or request |
| `documentation` | `0075ca` | Improvements or additions to documentation |
| `refactor` | `8250df` | Behavior-preserving restructure, no functional change |
| `chore` | `fef2c0` | Tooling, deps or housekeeping, no behavior change |

The first three are GitHub's own defaults, colour and description included, so a fresh repo already carries them and only `refactor` and `chore` are created.

### Size

How much of the codebase the change moves. It is the effort estimate a maintainer reads before picking up an issue, not a time estimate.

| Label | Colour | Description |
| --- | --- | --- |
| `XS` | `e4e4e7` | Trivial: one spot, minutes |
| `S` | `b4b4bb` | Small: surgical, about one file |
| `M` | `71717a` | Medium: multi-file or new path |
| `L` | `3f3f46` | Large: sweep or new module |
| `XL` | `18181b` | Extra-large: new subsystem, design-gated |

The greys run light to dark with size, so the axis reads as a ramp in the tracker's label column rather than as five unrelated colours.

### Priority

How much it costs to leave the issue undone.

| Label | Colour | Description |
| --- | --- | --- |
| `critical` | `b60205` | Production-breaking, no workaround |
| `high` | `d93f0b` | Broken functionality or active exposure |
| `med` | `fbca04` | Should do: value but not urgent |
| `low` | `0e8a16` | Nice to have: no urgency |

Red through amber to green, the same ramp as the role labels, so the two columns read together.

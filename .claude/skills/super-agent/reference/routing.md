# Routing: the ask answer

`scripts/` is under this skill's base directory. `route.sh` answers `ask: true`
when `wanted` sits above the default tier while the chosen instance's weekly
bucket has under 50% remaining. Launch then answers `ask`, and you escalate
first (Needs you, with an AskUserQuestion offering `wanted` and `tier`, your
recommendation first, naming `bucket` and `reason`), then rerun launch with
`--wanted yes` or `--wanted no`. An unknown quota never asks. `no_instance`
goes to Needs you with route's `reason`.

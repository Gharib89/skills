# Routing: the ask answer

`scripts/` is under this skill's base directory. `route.sh` answers `ask: true`
when `wanted` sits above the default tier while the chosen instance's weekly
bucket has under 50% remaining. Launch then answers `ask`, and you escalate
first (a need, reason `route-ask`, its options `wanted` and `tier`, your
recommendation first, its why naming `bucket` and `reason`),
then rerun launch with `--wanted yes` or `--wanted no`. An unknown quota never
asks. `no_instance` is a need, reason `no-instance`, its why route's `reason`.

When an instance's weekly bucket resets within the hour, route drops its
weekly reserve to 0, so queued work spends what the week has left, your own
thread's share included; its 5 hour floor still holds, and a weekly bucket at
0 still skips it.

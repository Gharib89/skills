# Routing: the ask answer

`scripts/` is under this skill's base directory. `route.sh` answers `ask: true`
when `wanted` sits above the default tier while the chosen instance's weekly
bucket has under 50% remaining. Launch then answers `ask`, and you escalate
first (Needs you, with a chat question offering `wanted` and `tier` as
numbered options, your recommendation first, naming `bucket` and `reason`),
then rerun launch with `--wanted yes` or `--wanted no`. An unknown quota never
asks. `no_instance` goes to Needs you with route's `reason`.

In the last hour of a weekly window, when an instance's weekly bucket resets
within 60 min, route drops that instance's weekly reserve to 0, so queued work
spends what the week has left; its 5 hour floor still holds, and a weekly
bucket at 0 still skips it. Nothing is held back for your own thread.

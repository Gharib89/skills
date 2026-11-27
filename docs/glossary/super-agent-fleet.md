### Super agent: fleet and placement

**Fleet file**:
The owner's user-scope file, written by the super agent's setup step and carried to every machine, that lists what the super agent may use: each linked machine with its capabilities and slot count, each provider instance with its quota read and auth result, the GitHub accounts, the active repos (each with its ship cap and machine pin), the default standing waivers, who rules on a merge-gate hold and the notify command. Each linked machine also carries its `ssh` string (`user@host` or a config alias), recorded only after a key-only test passed, and the file may hold a **check-only machine**. The skill itself names none of these, so it stays the same for every owner.
_Avoid_: config, inventory, profile (a ship profile is per repo)

**Machine check**:
One fixed, read-only check of a fleet machine over its `ssh` string, run by `machine-check.sh <machine> <check>`: `up`, `load`, `disk`, `gpu`, `t3`, `clis`, `process <name>` or `log <unit> [lines]` (at most 200). There is no free-form command and no sudo: a read denied to the user prints `needs-root`, and an unreachable host is one attempt that prints `unreachable` with SSH's reason and changes no placement. An asked check runs inline in the super agent's thread, and the call guard refuses a direct `ssh`, `scp` or `rsync` call, so the script is the only route.
_Avoid_: remote command, SSH probe, health check

**Check-only machine**:
A machine in the fleet file with an `ssh` string, no T3 environment id and `check_only: true`: a machine check reads it, and placement never puts work on it.
_Avoid_: monitored host, unlinked machine

**Provider instance**:
One T3 provider the super agent may launch on, named by T3's instance id: two Claude accounts are two instances of one driver, Pi another. Each is signed in and read for quota under its own account directory, so the fleet file keys its providers by instance id and routing picks the instance with the most weekly headroom, skipping one that is signed out; two instances on one account read the same buckets. An instance's **weekly weight** (a number, default 1, the owner's) says how many times larger its weekly quota is than another's, so headroom is its weekly remaining times that weight: 40% of a seat three times the size outranks 60% of the small one. Two fractions in the fleet file set the **floors**: an instance whose weekly bucket is under the weekly reserve, or a `claude` instance whose 5 hour bucket is under the 5 hour floor, is skipped, and the route's reason names which.
_Avoid_: account, provider (that is the driver), subscription

**Slot**:
One supervised thread a machine may run at once. The fleet file sets each machine's slot count as a ceiling, less the slots it keeps for the owner's messages (`reserve`, 1 on the super agent's own machine); a launch still checks the machine's free memory and load before it takes a slot. A probe thread and an interactive task take none. The `fleet` script sets it. A slot bounds a machine; the **ship cap** bounds a repo.
_Avoid_: worker, lane, seat

**Placement**:
Choosing the machine a launch runs on: the super agent's own machine first, a GPU machine for GPU work, the next reachable linked machine that fits when one is down, and a row in the ledger's waiting list when none does, a launch over its repo's ship cap included. A repo the fleet file pins to a machine (a **machine pin**) is placed there alone, and waits when that machine is down or full. Work is placed on a machine only through its T3 environment id, and only if the owner already linked it (ADR 0023).
_Avoid_: scheduling, load balancing

**Ship cap**:
The most supervised threads one repo may have open at once, across every machine, set per repo in the fleet file as `max_ships` (3 when unset). It counts every open thread of the repo, ship and triage alike, so a launch over it becomes a waiting row naming the cap. Different from a slot, which is a machine's ceiling.
_Avoid_: repo limit, concurrency limit, quota (that is a provider's)

### Supervision

**Supervisor**:
The main agent in a `drive-session` run: it spawns supervised sessions, waits on all of them with one background `watch`, reads each event, and answers it or escalates it to the human. A supervised `/ship` treats it as the human present, so the run is attended.
_Avoid_: orchestrator, driver, parent session, main session

**Supervised session**:
One Claude agent in a Herdr tab the supervisor created, beside its own tab, recorded as a row of the roster. The supervisor touches no session the roster does not hold.
_Avoid_: child session, worker, sub-session, spawned agent

**Roster**:
The JSON file listing a supervisor's supervised sessions, one row each with its name, pane, tab, task and the sequence number last acknowledged. It is how a compacted or resumed supervisor still knows which sessions it owns.
_Avoid_: session list, registry, run file alone (that is ship's)

**Escalation**:
A supervised session's question the supervisor forwards to the human instead of answering: a merge gate the merge allowance does not cover (none granted, or the gate held by anything but a reviewer rule), an approval for a destructive command, every permission dialog (one approving a tool call, not the startup trust dialog), or a fork in scope, schema or architecture. It names the session, quotes the question and carries a proposed answer.
_Avoid_: hand-off (that is ship's stop), question, ping

**Merge allowance**:
The launch prompt's permission for the supervisor to answer a supervised ship run's merge gate with "merge" when that gate is clean, by Ship's own `run-file gate clean` verdict, and on a gate held only by reviewer rules (a reviewer's cap after a clean local review, or a small lane or cap answered by one more host round on the final head). Without it, or on a gate held by any other reason or an unmet criterion, the merge gate is an escalation.
_Avoid_: auto-merge, merge permission, `Merge: on-clean-gate` (that is the ship profile's opt-in)

**Spec batch**:
A supervisor's drive of one spec parent's sub-issues to merge, each as a supervised `/ship` run, at most two at a time and only when no blocking edge joins them and the areas their briefs name do not overlap. It ends when every sub-issue it can reach is at rest.
_Avoid_: supervised batch, spec run (run is ship's), wave

**Batch log**:
A spec batch's running list of finds, one line each naming the run, what happened and whether it would recur in the runs still to come. A recurring find is fixed before the slices it would hit; the rest become the retro drafted at the batch's end.
_Avoid_: notes, journal, retro (that is what the log becomes)

# Super-agent incidents: questions, unasked actions, asks and messages

Part of [the incident research](super-agent-incidents.md), which holds the
sources, the basis labels (measured, recorded, inferred, guess), the session
table (S1 to S5) and the ranked causes.

## 2. A question answered by a corrective action

**What the skill said.** Nothing. `grep -n -i why` over `SKILL.md` and
`reference/` finds no rule about an owner question (**measured**). The nearest
text pushes the other way: Escalation opens with "The owner decides these, and
you decide everything else", at every commit read (**measured**).

The owner asked "why" 11 times across the five sessions (**measured**: `grep`
over owner-typed messages).

- **11-12 12:36.** Asked why an issue was still open. The reply explained (no
  PR had closed it, its label left closing to the owner) and then said it had
  tried to post a closing comment and close the issue, and that the harness
  permission check had blocked the write because the owner had only asked why
  (**measured**: S2, the super agent's own words). The only brake was the
  harness, not the skill.
- **11-19 15:29.** Asked why two ship threads ran on the super agent's machine
  when the owner had named a linked one. The first reply, one minute later,
  announced a relaunch. The explanation came at 15:33, after it had stopped
  both threads, removed their worktrees, pushed one thread's commit and
  relaunched both (**measured**: S5). The stated cause: it passed the wrong
  machine key, taken from "my own notes written before the context reset".
- **11-19 16:25.** Asked why a thread was not checked (1b). The same reply that
  explained also reported that it had told the thread to merge (**measured**:
  S5). It held the merge-gate ruling by then, so the action was allowed; the
  owner still got an action where a question was asked.
- **11-09 10:51.** Asked when tickets get assigned. The reply was a status line
  about the watcher and the next triage. The owner repeated the question three
  minutes later and was answered (**measured**: S1). **Inferred**: the question
  arrived mid-wake and the turn finished its own work first.

Counter-examples, all **measured**: on 11-09 11:53, 11-11 12:55, 11-15 12:41
and 11-19 14:56 the reply gave a specific cause and either offered the fix and
waited, or admitted its own error.

Cause: **missing rule**. Three things follow for the design:

- The failure is acting, not being unable to explain. In every case read the
  explanation named a script, a file or a recorded ruling, and the two checked
  against tool calls here (1b, and 3 below) were accurate (**measured** for
  those two, **inferred** for the rest). No invented explanation was found.
- One explanation did rest on the super agent's own pre-compaction notes, and
  those notes were the wrong input in the first place (11-19 15:29).
- So the evidence supports an ask-first rule strongly and a decision log
  weakly (**inferred**).

## 3. An action nobody asked for

- **11-09 11:03.** The owner asked the super agent to watch a grill thread the
  owner was running. When that thread paused on a question for the owner, the
  super agent answered it in the thread, "on the owner's standing rule (take the
  recommended option when defensible)", and told it to file three issues and
  fix one inline (**measured**: the `t3_thread_send` call in S1). The skill
  then said "Touch only threads the ledger holds and the probe threads you
  launch", and that thread was in no ledger entry. Cause: **rule in prose
  only**, against "you decide everything else".
- **11-12 12:36.** The attempted close in section 2.
- **11-19 15:24.** The wrong-machine launch in section 2. `launch.sh` takes
  `--machine <key>` as given and never compares it with the host's name
  (**measured**: `grep -n hostname scripts/*.sh`; only `place.sh`,
  `launch-check.sh` and `setup.sh` read it, as a default when a flag is
  omitted). Cause: **context lost after compaction**, let through by a
  **script gap**. The owner recorded the machine's own key as a ruling
  afterwards (**measured**: ledger ruling of 11-19).
- **11-19 11:14.** The owner had asked for the consumer repos' skills to be
  refreshed once the ship tickets merged. The super agent launched task threads
  with a refresh prompt it wrote itself. The owner corrected it: the refresh
  runs through the `update-skills` skill. Both threads had already opened PRs
  from the hand refresh, closed them and started again (**measured**: S5). On
  11-13 the owner had asked for the same job "running update-skills"
  (**measured**: S3). Cause: **missing rule** (a task thread's first message is
  free text the super agent writes; nothing maps a job to its owner skill),
  with **context lost** between threads as the likely reason the earlier
  wording was gone (**inferred**).
- **11-19 14:56.** A ship was launched with no `--area`, which the placement
  rules read as overlapping every ticket in the repo, so the next ticket in
  that repo waited. The super agent first told the owner that only one ticket
  per repo runs at a time, and corrected that when asked why (**measured**:
  S5). Cause: **rule in prose only** (areas are "judged from the issue"), with
  a silent script default.
- **Recorded by the 11-18 audit** (#1276, #1279, #1287): it forged a quota
  read, edited a fleet key under the wrong name, added a label to steer the
  skill choice, reset stall counts by hand, and merged 5 PRs itself, one ending
  in a false need. One of these is visible here: a schedule prompt the super
  agent wrote on 11-12 told its own next wake to lower a floor in the fleet
  file by hand "for this wake only" and restore it after (**measured**: S2).
  Cause: **script gap**, no supported override. Built since: override flags
  (v0.32.0) and the guard hook (v0.35.0).

## 4. An ask to watch an existing thread, or to take one over

**Watch.** Two asks went badly, both on 11-09 and both about the same
owner-run thread (**measured**: S1).

- The thread ran in the repo's main checkout, so the ledger could not hold it
  (no worktree, which reconcile reads as a mismatch). The super agent watched
  it with a polling script it wrote itself (**measured**: S1 Bash call, and the
  ledger rulings of 11-09 that say "hand-watched").
- It then answered the owner's question inside that thread (section 3). The
  owner repeated "watch the thread" one minute later. Two rulings followed: do
  not settle that thread until the owner says so, and never remove its
  worktree.

The skill had no `adopt` then. After v0.17.0 added it, the ledger shows 10
adopted entries, all settled (**measured**: `jq` on `adopted`). The only
trouble found with them is 1d: three of the ten are one thread adopted again
and again.

**Take over.** No misread take-over ask was found. `pause` and `unpause`
shipped in v0.32.0 on 11-18, and neither the ledger nor its archive holds a
paused entry (**measured**: `grep -c paused`). In S4 and S5 the owner twice
said they would handle a ticket in their own thread, and the super agent
dropped it from its waiting list without incident (**measured**). What the
sessions do show is the reverse case: before 11-09 an entry was dropped once the
owner stepped into its thread (1c), which the 11-09 ruling and the "owner steps
into a supervised thread" paragraph answer. Whether "take control" in #1310
means `pause`, or something the owner wants from the phone UI, is a **guess**
either way.

## 5. A non-ticket ask refused, done inline or mishandled

No refusal was found in any session (**measured**: no reply to a non-ticket ask
declines it). No ask for a plain test run was found either; probes ran as
scratch threads without incident. The mishandled ones:

| Date | The ask | What happened | Cause |
|---|---|---|---|
| 11-09 | A grill the owner answers | Recorded as a triage entry, settled at first rest, its PR merged unseen (1c) | Script gap, built since (v0.12.0, `interactive` in v0.32.0) |
| 11-10 | A deploy thread | Checked "by hand on each wake", a line carried in the super agent's own compaction prompt. The retro records it was stored as a triage entry that read closed from its first second | Script gap, built since (v0.17.0). measured: S1; recorded: #1146 |
| 11-11 | A fix thread with no issue, twice | "The ledger can't track them and I check them by hand each wake" | Script gap, built the same night (v0.17.0). measured: S2 |
| 11-10, 11-12, 11-14 | Research questions | Answered inline in the pinned thread. The 11-14 answer is 5,015 characters | Missing rule: the "never done inline" sentence (v0.29.0) names secret rotation and dotfiles only. measured: S2, S3 |
| 11-13 | A recurring check: tell me when a quota bucket reaches 1% | A background loop the super agent wrote, reading quota every 4 minutes. It worked: the alert came 22 minutes later | Missing feature: the skill has no recurring kind (measured: `grep -i recurring`) |
| 11-15 | A long task on a linked machine | Re-added to the ledger four times (1d) | Script gap |
| 11-19 | Refresh the consumer repos' skills | Done with a hand-written prompt, then redone through the owner skill (section 3) | Missing rule |

## 6. Over-long messages and noisy pushes

**What the skill said.** Since v0.14.0 the status block is "printed by a
script, silent when nothing changed"; since v0.33.0 the super agent posts
`status.block` as printed and pushes each unpushed need; since v0.34.0 a pulse
with `end_turn` true "posts nothing". There is no rule on a message's length
(**measured**: `grep -n -i -E 'length|short|concise'` over `SKILL.md` and
`reference/status-block.md` finds none).

| Session | Assistant messages | Median, 90th percentile, longest (characters) | Over 1,500 characters | Say nothing is needed or nothing changed | Mention that the watcher is running | Push calls | Question dialogs |
|---|---|---|---|---|---|---|---|
| S1 | 397 | 263, 1,296, 5,268 | 20 | 45 | 54 | 11 | 10 |
| S2 | 536 | 330, 1,141, 11,792 | 25 | 64 | 116 | 9 | 8 |
| S3 | 264 | 186, 1,274, 5,015 | 14 | 33 | 89 | 1 | 16 |
| S4 | 138 | 191, 1,044, 2,808 | 8 | 13 | 43 | 0 | 4 |
| S5 | 134 | 467, 1,509, 2,559 | 15 | 25 | 55 | 7 | 0 |

All **measured**: `jq` and `grep` over each transcript's assistant text and
tool calls.

- **11-10 06:51.** The owner asked for an easy, concise way to stay updated
  (**measured**: S1). The retro of that day records that the owner asked for
  status eight times and that 82 of 173 wakes did no work (**recorded**: #1140).
- **11-10 to 11-18, recorded.** `status.sh` ran 4 times in about 260 wakes, the
  audit counted 1 push for 17 needs, and question dialogs blocked the loop for
  about 9.5 hours (**recorded**: #1276, #1281).
- **11-15 12:40.** A push told the owner a PR was not merged and asked them to
  merge it by hand; the owner's comment on it was that they had asked the super
  agent to merge (**measured**: S3).
- **11-15 12:41.** Every triage thread's first message carried ship's merge
  block; the 11-16 grill counted 19 lines beside the invocation (**measured**:
  S3, and the grill thread's first slice). Fixed by v0.23.0 and v0.25.0.
- **S5, on v0.37.0, after every fix above.** Still 134 messages in one day, 25
  of them saying nothing is needed or nothing changed. 12 needs were recorded
  and 7 pushes sent; one need was pushed twice, 30 minutes apart, the second
  saying it "still waits on you". At 16:00 and 16:09 two wakes in a row
  repeated the same pending question. At 16:12 a need was recorded whose action
  reads "Nothing yet", to quiet a stall row, and it then showed under "Needs
  you" (**measured**: S5 Bash and push calls).

Cause: **rule in prose only**. The scripts print the rows, and the model still
writes text around them on every wake, so length follows what it read. The
"Nothing yet" need is a **script gap**: recording a need is the only way to
silence an escalate row, so a row that needs nothing becomes a need.

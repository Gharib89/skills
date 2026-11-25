# What a script can keep or decide, a script does

A guarantee the super agent keeps by remembering a sentence is only as good as its memory. "No turn ends without a watcher running while the ledger holds an open entry" sat in `SKILL.md` as prose: a promise only the model's memory kept, and a turn that ends with an open entry and no watcher wakes nothing when a supervised thread finishes, until the hourly backstop. Whatever a script can keep or decide, a script does.

## Considered Options

- **Keep the sentence and sharpen it (rejected):** the sentence was already plain, and more prose asks the same memory to do the same job.
- **A hook or timer that does the job itself (chosen where it can):** a Stop hook can refuse a turn end, and a timer outside the model can wake it; neither needs the super agent to remember anything.

## Consequences

- A guarantee lives in a hook or a timer outside the model. The **watch guard** is the first: a Stop hook that asks `watch.sh --owed` and refuses the turn end once while a watcher is owed. The super agent still starts the watcher itself, so a missing hook leaves the loop working and only the guarantee lost.
- A hook that cannot judge (no `jq`, an unreadable ledger, a failed check) allows the stop and logs it: a guard rail never becomes a gate on the turn.
- A routine wake's actions and text are a script's, not the model's: when a wake does the same thing every time, the script prints the words and the super agent posts them as printed.
- Each guard logs its blocks and passes beside the ledger, and the scorecard counts them, so a guard that never fires is a deletion candidate and a pass with the condition still true (the target is 0) is a bug to fix.
- This extends ADR 0020's rule that the super agent speaks only at step-ins: the same distrust of the model's memory, applied to what it must do rather than what it may say.

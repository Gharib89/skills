# Reads go over SSH, writes go over a T3 environment

The super agent reached every machine through its T3 environment id alone, and the glossary said so: "a machine is reached only through its T3 environment id". Reading a machine that way costs a scratch thread per question, so "is the laptop up" or "tail the deploy log on the server" became a thread launch, and a machine the owner wants watched but never worked on could not be read at all. Key-only SSH answered on every machine of the owner's in 1 to 4 seconds (measured in #1321). This decision reverses that glossary sentence: a machine is now reached two ways, and which way depends on whether the call reads or writes.

## Considered Options

- **Everything through T3 environments (rejected):** every read becomes a scratch thread, and a machine with no T3 server cannot be read.
- **SSH for everything (rejected):** launching and steering work over SSH bypasses T3's threads, the ledger and the call guard's send rules.
- **Free-form SSH commands for reads (rejected):** read-only would rest on the model choosing harmless commands.
- **Reads over SSH through fixed checks, writes over T3 (chosen).**

## Consequences

- The fleet file gains one `ssh` string per machine (`user@host` or a config alias). Setup proposes it from the linked environment's own host name, tests it key-only and records it only when the test passes, and does not add a linked machine whose test fails. A **check-only machine** (an `ssh` string, `check_only: true`, no environment id) is read and never placed on.
- A **machine check**, `machine-check.sh <machine> <check>`, is the only read the super agent asks for: eight fixed, read-only checks, no free-form command and no sudo (`needs-root` instead). Every call is batch mode, never accepts a new host key, and makes one attempt with a 6 second connect timeout; an unreachable host is an answer, `unreachable` with SSH's reason, and never changes placement, which keeps T3's own reachability.
- The call guard refuses a direct `ssh`, `scp` or `rsync` call, so the script is the only route. It reads the command's text, a speed bump against a slip rather than a sandbox.
- Amended by #1383: scripts make two more fixed reads with the same SSH options, never a command the model writes. The watcher, reconcile and `launch record` read a linked machine's threads with `t3 thread show` there (`lib/remote.sh`), and setup and placement read its load with `probe.sh` (`sa_ssh_probe` in `lib/ssh.sh`). `t3 thread show` has no environment flag, so the T3 environment route cannot answer that read.
- Launching, steering and anything that writes (a worktree removal included) stay on T3 environments.
- An asked machine check runs inline in the super agent's own thread, the one exception to launching an owner's non-routing ask as a task thread.

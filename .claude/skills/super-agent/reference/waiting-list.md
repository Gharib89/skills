# The waiting list

## Contents

- [Recording](#recording)
- [Ready and dropped rows](#ready-and-dropped-rows)

The owner's word "queue" is the ledger's waiting list. It holds tickets with no
thread yet: the ones placement could not place (a machine or the ship cap was
in the way) and the ones the owner queued.

## Recording

- "Add N to the queue": `ledger.sh wait <key> --reason queued`. Every key is
  the full `<owner/name>#<n>`: expand the owner's bare numbers with the repo
  they are talking about. `wait` refuses a ticket that has an open thread.
  Rows with no `--order` run oldest first, after the ordered ones.
- "Put N first": `ledger.sh wait <key> --reason queued --order <n>`, lowest
  first, 0 allowed, up to 9 digits. A repeat `wait` keeps the order and
  blocker it is not given.
- "Take N off the queue": `ledger.sh unwait <key>`.
- "Ship M after N": `ledger.sh wait <M> --after <N> --reason "after <N>"`. N is
  any ticket's key, in this repo or another, and must merge first. `--after` is
  the ledger's own: it adds no blocking edge on GitHub, which stays the record
  there.

Say what you recorded in one line. The owner's queueing words are the go the
hard rule "launch only on the owner's go" asks for, so none is asked again.

## Ready and dropped rows

Reconcile reads every waiting row. Read `list`'s `waiting` only after a
reconcile, since a row whose issue closed stays on it until then.

- `ready`: the rows that could launch now, in the list's order. A row is ready
  when it has no blocker or its blocker merged (its entry `merged` or
  `settled`, or, with no such entry, its issue closed and not as not planned),
  and its repo is under its ship cap, `max_ships` in the fleet file (3 when
  unset), counting the repo's open entries and the ready rows ahead of it.
  Launch each through the loop's launch step, which still places it: a row
  that comes back `waiting` stays on the list. A row placement wrote becomes
  ready the same way.
- `dropped`: a row whose issue closed, already removed from the ledger.
- A row whose issue or blocker cannot be read stays, is not ready and is in
  `errors` as `issue-unreadable`, its `detail.key` the issue that failed. Run
  reconcile with `--fleet`, or every repo gets the default cap of 3.

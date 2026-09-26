# Cloud probe: setup cache and idle restart (2026-09-26)

Both in `Default` (env_01JP2VM3dbgtAjtNh8um94pq), relayed by the user.

## Run 2b, a second new session (session_01R4ZyNDLGa8cbbc9zq9ji41)

    ae7a55da-992e-42be-96c4-6e0292079fbe          (boot_id)
    2026-09-26 21:46:48                           (up since)
    run 2026-09-26T21:46:55Z pwd=/home/user/repo user=root home=/root

A new session about 7 minutes after run 1b's setup (21:40:00) got a fresh VM and ran the
setup script again: the log holds only its own line. No reuse of run 1b's setup snapshot
was observed at that interval.

## Run 1b resumed after idle (session_01GpdNgpC5jwhAdG24yWtqrk)

    a40bf1b2-102e-4189-9ce0-315472dadcb9          (boot_id; probe run saw 121f7eea..., up 21:39:52)
    2026-09-26 21:49:13                           (up since)
    first-run: 2026-09-26T21:40:30Z boot=121f7eea-...
    stop.log:  2026-09-26T21:42:58Z
    run 2026-09-26T21:40:00Z ...                  (setup.log unchanged)
    sessionstart.log: 21:40:01Z and 21:49:21Z

Turn ended 21:42:58; the next message (about 6 minutes later) found a restarted kernel on a
preserved disk: `/tmp`, the checkout and a local commit survived. The setup script did not
re-run; the SessionStart hook did, 8 s after boot. The session reports `git remote -v` is
empty in its checkout, which is why its results push never reached GitHub.

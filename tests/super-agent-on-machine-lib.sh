# A linked machine the fake `ssh` runs commands on (tests/super-agent-fake.sh): its
# own cores, memory, load and GPU, which a `probe.sh` run over ssh reads. Source it
# after tests/super-agent-fake.sh.

# sa_on_machine <ssh target> <helper> [<args>]: run an sa_thread, sa_machine, sa_load or
# sa_gpu_failing call for the machine `ssh <target>` runs commands on (the fakes
# there answer from machines/<target>/, its own `bin/` first on PATH), so a
# `probe.sh` run over ssh reads that machine's cores, memory, load and GPU, not this one's.
sa_on_machine() {
  local m=$SA_FAKE/machines/$1
  shift
  mkdir -p "$m/probe" "$m/bin" "$m/threads"
  # shellcheck disable=SC2034  # SA_BIN is sa_machine's, read in the helper called here
  (SA_FAKE=$m SA_BIN=$m/bin; "$@")
}

# `--remote <environment id>=<dir>`, repeatable: where the super agent saved its
# reads of the threads on that linked machine, one `<thread id>.json` each. `t3
# thread show` has no environment flag (measured 2026-11-06), so a remote entry
# is read from these files, which the super agent writes with `t3_thread_read`.
sa_remote_dirs='{}'
# sa_remote_flag <usage> <value>: one `--remote` value into $sa_remote_dirs.
sa_remote_flag() {
  case $2 in ?*=?*) ;; *) sa_tooling "$1" ;; esac
  sa_remote_dirs=$(jq -c --arg k "${2%%=*}" --arg v "${2#*=}" '.[$k] = $v' <<<"$sa_remote_dirs")
}

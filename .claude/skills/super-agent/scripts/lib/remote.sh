# A linked machine's threads, read with the T3 CLI on that machine over SSH (ADR
# 0023): `t3 thread show` has no environment flag, so the CLI that knows the thread
# is the one on its machine. One call per machine per look covers every open thread
# there. `watch`, `reconcile` and `pulse` (through reconcile) read through it.
source "$(dirname "${BASH_SOURCE[0]}")/ssh.sh" || { printf '{"error":"cannot source lib/ssh.sh"}\n'; exit 2; }

# sa_remote_read <fleet file> <entries>: one SSH call per machine holding one of the
# entries (a JSON array; those with no `environment_id` are skipped), found by its
# `environment_id` in the fleet file's `machines`, over that machine's `ssh` string
# (lib/ssh.sh). Sets $sa_remote_lines, {<thread id>: <the `t3 thread show --json`
# line>}, and $sa_remote_down, {<environment id>: {machine, reason, detail}}: reason
# `no-ssh` for an environment no fleet machine with an `ssh` string holds, `ssh` for
# a call that failed, `detail` ssh's reason; and $sa_remote_up, the machines read
# fine. A fleet file it cannot read holds no machine.
sa_remote_lines='{}' sa_remote_down='{}' sa_remote_up='[]'
sa_remote_read() {
  local fleet=$1 envs env machine target ids cmd out err rc
  sa_remote_lines='{}' sa_remote_down='{}' sa_remote_up='[]'
  envs=$(jq -c '[.[] | .environment_id // empty] | unique' <<<"$2")
  [ "$envs" != '[]' ] || return 0
  while IFS= read -r env; do
    machine=$(jq -r --arg e "$env" 'first((.machines // {}) | to_entries[] | select(.value.environment_id == $e and (.value.ssh | type) == "string") | .key) // empty' "$fleet" 2>/dev/null </dev/null)
    target=$(jq -r --arg m "$machine" '.machines[$m].ssh // empty' "$fleet" 2>/dev/null </dev/null)
    if [ -z "$machine" ] || [ -z "$target" ] || [[ $target == -* ]]; then
      sa_remote_down=$(jq -c --arg e "$env" --arg m "$machine" '.[$e] = {machine: (if $m == "" then null else $m end), reason: "no-ssh", detail: null}' <<<"$sa_remote_down")
      continue
    fi
    ids=$(jq -r --arg e "$env" '.[] | select(.environment_id == $e) | .thread | @sh' <<<"$2" | tr '\n' ' ')
    # one line per thread, `<id>\t<its JSON line>`; the CLI's migration warning is on stdout, so the JSON line is picked out there
    cmd="for t in $ids; do printf '%s\\t' \"\$t\"; t3 thread show \"\$t\" --json --messages 1 2>/dev/null | grep '^{\"' | tail -n 1 | tr -d '\\n'; echo; done"
    err=$(mktemp) || return 1
    out=$(ssh "${sa_ssh_opts[@]}" "$target" "$cmd" 2>"$err" </dev/null); rc=$?
    if [ "$rc" -ne 0 ]; then
      sa_remote_down=$(jq -c --arg e "$env" --arg m "$machine" --arg d "$(sa_ssh_reason "$(cat "$err")")" '.[$e] = {machine: $m, reason: "ssh", detail: $d}' <<<"$sa_remote_down")
    else
      sa_remote_up=$(jq -c --arg m "$machine" '. + [$m]' <<<"$sa_remote_up")
      sa_remote_lines=$(jq -c --slurp --raw-input 'reduce (split("\n")[] | select(contains("\t")) | split("\t")) as [$t, $l] ({}; .[$t] = $l)' <<<"$out" \
        | jq -c --argjson s "$sa_remote_lines" '$s + .')
    fi
    rm -f "$err"
  done < <(jq -r '.[]' <<<"$envs")
}

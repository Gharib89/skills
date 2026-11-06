# Fake `t3`, `gh` and process tools for super-agent's tests: they answer from
# files under $SA_FAKE and record every call. Sourced, never run.
#
#   bin=$(mktemp -d); source tests/super-agent-fake.sh; sa_fake_install "$bin"
#   export PATH="$bin:$PATH" SA_FAKE=<state dir>
#   sa_thread t-1 running 1 0 /wt/one feat/one-5
#   sa_pr Gharib89/skills feat/one-5 open
#
# `t3 thread show <id> --json` answers `{thread, messages}` from
# `threads/<id>.json`, after the multi-line migration warning the real CLI
# prints on STDOUT (measured on 2026-11-06, so a script has to pick out the
# JSON line); no file is a thread the server does not know: exit 1.
# `SA_T3_RC` makes a found thread exit nonzero after its answer. `gh api
# <endpoint>` answers from `gh/<endpoint with every character outside
# [A-Za-z0-9._-] turned into _>`; no file is a 404, exit 1 with the JSON body
# on stdout like the real CLI (measured 2026-11-06). A POST to an endpoint
# ending `/comments` appends the `body=` field to that route's array, as
# `{id, body, created_at, user}` (the `now` file sets the time, the `user` route's login the author), and
# a DELETE removes its id from every comments route; any other POST answers `{}`
# or its route file. `pgrep` and `ps` record
# themselves in `proc-calls` and print nothing: a script that matches a
# process by name shows up there. Every t3 and gh call is a line of `calls`.
#
# For `setup`'s probes: `t3 environment list --json` prints the migration
# warning then `environments.json` (no file: exit 1); `gh auth status --json
# hosts` answers `gh-auth.json`, the real shape (measured 2026-11-06); `nproc`,
# `free -m`, `uptime`, `nvidia-smi` and `hostname` answer from `probe/` (sa_machine
# sets them; no GPU line is no tool, sa_gpu_failing a tool that fails; sa_load
# sets the load and the available memory, 0.50 and 21004 MB until then); `claude`, `codex` and `agy` answer from
# `provider/<name>.out` and `.rc` (sa_provider; no .rc is exit 0), and a
# provider named in SA_FAKE_ABSENT at install time is not installed; `agy` also
# records the directory it was run in and that directory's git common dir, a line of
# `agy-cwd`. `sleep` runs
# the one-shot script `on-sleep` first, to change what the fakes answer while a
# script waits.

sa_fake_install() { # <dir>
  cat > "$1/t3" <<'FAKE'
#!/usr/bin/env bash
printf 't3 %s\n' "$*" >> "$SA_FAKE/calls"
warn() { printf '%s\n' '[09:53:24.008] WARN (#20): Database migration history diverges from this build. {' \
  "  divergent: [" "    '77:Repair (unknown to this build)'" "  ]" "}"; }
if [ "$1 $2" = "environment list" ]; then
  warn
  [ -f "$SA_FAKE/environments.json" ] || { echo "environment list failed" >&2; exit 1; }
  cat "$SA_FAKE/environments.json"; exit 0
fi
[ "$1 $2" = "thread show" ] || { echo "fake t3: unsupported: $*" >&2; exit 2; }
id=$3
warn
f="$SA_FAKE/threads/$id.json"
[ -f "$f" ] || { echo "thread $id not found" >&2; exit 1; }
cat "$f"
exit "${SA_T3_RC:-0}"
FAKE
  cat > "$1/gh" <<'FAKE'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$SA_FAKE/calls"
if [ "$1 $2" = "auth status" ]; then
  [ -f "$SA_FAKE/gh-auth.json" ] || { echo "gh: not logged in" >&2; exit 1; }
  cat "$SA_FAKE/gh-auth.json"; exit 0
fi
[ "$1" = api ] || { echo "fake gh: unsupported: $*" >&2; exit 2; }
shift; method=GET ep='' body=''
while [ $# -gt 0 ]; do
  case $1 in
    -X|--method) method=$2; shift 2 ;;
    -f|-F|--field|--raw-field) case $2 in body=*) body=${2#body=} ;; esac; shift 2 ;;
    -*) shift ;;
    *) [ -n "$ep" ] || ep=$1; shift ;;
  esac
done
route() { printf '%s' "$1" | sed 's/[^A-Za-z0-9._-]/_/g'; }
f="$SA_FAKE/gh/$(route "$ep")"
case $method in
  POST)
    case $ep in
      */comments)
        # A new comment joins the issue's list, after the one-shot `on-post` script ran (a rival's claim landing first).
        if [ -f "$SA_FAKE/on-post" ]; then bash "$SA_FAKE/on-post"; rm -f "$SA_FAKE/on-post"; fi
        [ -f "$f" ] || echo '[]' > "$f"
        c=$(jq -c --arg b "$body" --arg t "$(cat "$SA_FAKE/now" 2>/dev/null || echo 2026-11-06T12:00:00Z)" \
          --arg u "$(jq -r '.login // "octo"' "$SA_FAKE/gh/user" 2>/dev/null)" \
          '{id: (([.[].id] | max // 1000) + 1), body: $b, created_at: $t, user: {login: $u}}' "$f")
        jq -c --argjson c "$c" '. + [$c]' "$f" > "$f.new" && mv "$f.new" "$f"
        printf '%s\n' "$c" ;;
      *) if [ -f "$f" ]; then cat "$f"; else echo '{}'; fi ;;
    esac ;;
  DELETE)
    id=${ep##*/}
    for g in "$SA_FAKE"/gh/*_comments*; do
      [ -f "$g" ] || continue
      jq -c --argjson i "$id" 'map(select(.id != $i))' "$g" > "$g.new" && mv "$g.new" "$g"
    done
    echo '{}' ;;
  *)
    [ -f "$f" ] || { printf '%s' '{"message":"Not Found","status":"404"}'; echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
    cat "$f" ;;
esac
FAKE
  cat > "$1/sleep" <<'FAKE'
#!/usr/bin/env bash
if [ -f "$SA_FAKE/on-sleep" ]; then bash "$SA_FAKE/on-sleep"; rm -f "$SA_FAKE/on-sleep"; fi
exec /usr/bin/sleep "$@"
FAKE
  for p in pgrep ps; do
    printf '#!/usr/bin/env bash\nprintf "%s %%s\\n" "$*" >> "$SA_FAKE/proc-calls"\n' "$p" > "$1/$p"
  done
  cat > "$1/nproc" <<'FAKE'
#!/usr/bin/env bash
cat "$SA_FAKE/probe/cores"
FAKE
  cat > "$1/free" <<'FAKE'
#!/usr/bin/env bash
printf '              total        used        free      shared  buff/cache   available\nMem:       %s       10410        5292        2471       18557       %s\nSwap:        8191           0        8191\n' "$(cat "$SA_FAKE/probe/ram_mb")" "$(cat "$SA_FAKE/probe/avail_mb" 2>/dev/null || echo 21004)"
FAKE
  SA_BIN=$1
  cat > "$1/uptime" <<'FAKE'
#!/usr/bin/env bash
l=$(cat "$SA_FAKE/probe/load" 2>/dev/null || echo 0.50)
printf ' 14:02:11 up 3 days,  2:11,  1 user,  load average: %s, 0.58, 0.59\n' "$l"
FAKE
  cat > "$1/hostname" <<'FAKE'
#!/usr/bin/env bash
cat "$SA_FAKE/probe/hostname"
FAKE
  for p in claude codex agy; do
    case " ${SA_FAKE_ABSENT:-} " in *" $p "*) continue ;; esac
    cat > "$1/$p" <<'FAKE'
#!/usr/bin/env bash
n=$(basename "$0")
printf '%s %s\n' "$n" "$*" >> "$SA_FAKE/calls"
[ "$n" != agy ] || printf '%s|%s\n' "$PWD" "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" >> "$SA_FAKE/agy-cwd"
cat "$SA_FAKE/provider/$n.out" 2>/dev/null
exit "$(cat "$SA_FAKE/provider/$n.rc" 2>/dev/null || echo 0)"
FAKE
    chmod +x "$1/$p"
  done
  chmod +x "$1/uptime" "$1/sleep" "$1/t3" "$1/gh" "$1/pgrep" "$1/ps" "$1/nproc" "$1/free" "$1/hostname"
  mkdir -p "$SA_FAKE/threads" "$SA_FAKE/gh" "$SA_FAKE/probe" "$SA_FAKE/provider"
}

# sa_machine <hostname> <cores> <ram_mb> [<gpu line>]: what the machine probes
# read. No GPU line removes `nvidia-smi`, a machine without the tool.
sa_machine() {
  printf '%s\n' "$1" > "$SA_FAKE/probe/hostname"; printf '%s\n' "$2" > "$SA_FAKE/probe/cores"
  printf '%s\n' "$3" > "$SA_FAKE/probe/ram_mb"; rm -f "$SA_BIN/nvidia-smi"
  [ -z "${4:-}" ] || printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\n' "$4" > "$SA_BIN/nvidia-smi"
  [ -z "${4:-}" ] || chmod +x "$SA_BIN/nvidia-smi"
}

# sa_load <load1> <available_mb>: the live readings `uptime` and `free -m` answer
sa_load() { printf '%s\n' "$1" > "$SA_FAKE/probe/load"; printf '%s\n' "$2" > "$SA_FAKE/probe/avail_mb"; }

# sa_gpu_failing: a machine whose `nvidia-smi` is there and fails, as after a driver mismatch
sa_gpu_failing() {
  printf '#!/usr/bin/env bash\necho "NVIDIA-SMI has failed" >&2\nexit 9\n' > "$SA_BIN/nvidia-smi"
  chmod +x "$SA_BIN/nvidia-smi"
}

# sa_provider <claude|codex|agy> <exit code> <stdout>: what its quota command prints
sa_provider() {
  printf '%s\n' "$3" > "$SA_FAKE/provider/$1.out"; printf '%s\n' "$2" > "$SA_FAKE/provider/$1.rc"
}

# sa_environments <json array>: what `t3 environment list --json` prints
sa_environments() { printf '%s\n' "$1" > "$SA_FAKE/environments.json"; }

# sa_github <login>...: the accounts `gh auth status --json hosts` lists, the first active
sa_github() {
  local first=true out='' l
  for l in "$@"; do
    out+=$(jq -cn --arg l "$l" --argjson a $first '{state:"success",active:$a,host:"github.com",login:$l}'),
    first=false
  done
  printf '{"hosts":{"github.com":[%s]}}\n' "${out%,}" > "$SA_FAKE/gh-auth.json"
}

# sa_thread <id> <status> <runCount> <pending> <worktree> <branch> [<last message>]
sa_thread() {
  jq -cn --arg id "$1" --arg s "$2" --argjson n "$3" --argjson p "$4" --arg w "$5" \
    --arg b "$6" --arg m "${7:-}" \
    '{thread: {threadId: $id, status: $s, runCount: $n, pendingRequestCount: $p,
       worktreePath: $w, branch: $b, pullRequests: [], settled: false},
      messages: (if $m == "" then [] else [{role: "assistant", runId: "r", text: $m}] end)}' \
    > "$SA_FAKE/threads/$1.json"
}

sa_route() { # <endpoint> <json>: what `gh api <endpoint>` answers
  printf '%s\n' "$2" > "$SA_FAKE/gh/$(printf '%s' "$1" | sed 's/[^A-Za-z0-9._-]/_/g')"
}

# sa_pr <owner/name> <branch> <open|merged|closed|none>: the PR list for a branch
sa_pr() {
  local repo=$1 branch=$2 state=$3 body
  case $state in
    open) body='[{"number":7,"state":"open","merged_at":null}]' ;;
    merged) body='[{"number":7,"state":"closed","merged_at":"2026-11-06T10:00:00Z"}]' ;;
    closed) body='[{"number":7,"state":"closed","merged_at":null}]' ;;
    none) body='[]' ;;
  esac
  sa_route "repos/$repo/pulls?head=${repo%%/*}:$(jq -rn --arg s "$branch" '$s | @uri')&state=all&sort=created&direction=desc&per_page=1" "$body"
}

sa_issue() { # <owner/name> <number> <open|closed>
  sa_route "repos/$1/issues/$2" "{\"number\":$2,\"state\":\"$3\"}"
}

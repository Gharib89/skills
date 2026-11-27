# The steps `launch.sh` shares between its forms, sourced by it before its `record` and
# `task` words: a script's answer (`sub`), the ledger write of a launch answer's
# `record`, the fleet and machine checks, the no-launch answer and the route. They read
# the caller's $here, $usage and flag variables.

# shellcheck disable=SC2154,SC2034  # here, usage and the flag variables come from launch.sh; route, use, selection, host, fields and base are read there

# sub <script> <args>...: one script's answer in $out and its exit in $rc. Its exit 2
# is this script's own, carrying its message.
sub() {
  local s=$1; shift
  out=$(bash "$here/$s.sh" "$@" 2>/dev/null </dev/null); rc=$?
  [ "$rc" != 2 ] || sa_tooling "$s: $(jq -r '.error // "failed"' <<<"$out" 2>/dev/null)"
}
# rec_fields <record>: a launch answer's `record` as the ledger flags in $fields.
rec_fields() {
  local a env br; env=$(jq -r '.environment_id // empty' <<<"$1") br=$(jq -r '.branch // empty' <<<"$1")
  fields=(${br:+--branch "$br"} --instance "$(jq -r .instance_id <<<"$1")"
    --model "$(jq -r .model <<<"$1")" --effort "$(jq -r .effort <<<"$1")" ${env:+--environment "$env"})
  while IFS= read -r a; do fields+=(--area "$a"); done < <(jq -r '.areas[]' <<<"$1")
}
# rec_add <record> <flag>...: `ledger add` its entry to $ledger, a task keyed by its
# slug (its repo kept, when it has one) or the ticket, with the flags given.
rec_add() {
  local r=$1 k tr; k=$(jq -r .key <<<"$r"); shift; rec_fields "$r"
  fields+=(--machine "$(jq -r .machine <<<"$r")" "$@")
  if [ "$(jq -r .kind <<<"$r")" = task ]; then
    [ "$(jq -r .interactive <<<"$r")" != true ] || fields+=(--interactive)
    tr=$(jq -r '.repo // empty' <<<"$r")
    sub ledger --ledger "$ledger" add --task "${k#task:}" ${tr:+--repo "$tr"} "${fields[@]}"
  else
    sub ledger --ledger "$ledger" add --repo "${k%#*}" --number "${k##*#}" --kind "$(jq -r .kind <<<"$r")" "${fields[@]}"
  fi
}

# fleet_ok: the fleet file and --machine checks every launch makes before anything else.
fleet_ok() {
  [ -f "$fleet" ] || sa_tooling "$fleet: no such file, run setup"
  jq -e '(.merge_gate_ruler // "owner") | IN("owner", "super-agent")' "$fleet" >/dev/null 2>&1 \
    || sa_tooling "$fleet: merge_gate_ruler must be \"owner\" or \"super-agent\""
  # --machine must be this machine: a key carried in the agent's notes would otherwise
  # pick where the thread runs and what the claim and the ledger say (#1332).
  host=$(hostname 2>/dev/null) || sa_tooling "cannot read this machine's name"
  jq -e --arg m "$machine" --arg h "$host" '.machines[$m] | type == "object" and (.hostname // $m) == $h' "$fleet" >/dev/null 2>&1 \
    || sa_tooling "--machine $machine is not this machine ($host) in $fleet: pass this machine's own fleet key, or run setup here"
  # An answer that does not launch leaves no file, so a stale one is never recorded.
  [ -z "$outf" ] || rm -f "$outf"
}
# answer <reason> <detail json>: no launch, exit 1
answer() { jq -cn --arg k "$key" --arg r "$1" --argjson d "$2" '{key: $k, launch: false, reason: $r, detail: $d}'; exit 1; }
# route_pick: route $size into $route, $use and $selection, or answer `no_instance` or `ask`.
route_pick() {
  sub route --size "$size" --quota "$quota" ${raise:+--raise "$raise"} ${named:+--instance "$named"} ${go:+"$go"}
  [ "$rc" = 0 ] && jq -e 'type == "object"' <<<"$out" >/dev/null 2>&1 || sa_tooling "route gave no answer"
  route=$out
  jq -e '.instance_id != null' <<<"$route" >/dev/null || answer no_instance "$(jq -c '{reason}' <<<"$route")"
  ask=$(jq -r .ask <<<"$route")
  if [ "$ask" = true ] && [ -z "$wanted" ]; then answer ask "$(jq -c '{wanted, tier, bucket, reason}' <<<"$route")"; fi
  use=tier; if [ "$ask" = true ] && [ "$wanted" = yes ]; then use=wanted; fi
  selection=$(jq -c --arg u "$use" '{instanceId: .instance_id}
    + (if $u == "wanted" then {model: .wanted_model, options: .wanted_options} else {model, options} end
       | with_entries(select(.value != null)))' <<<"$route")
}
# base_of <owner/name>: the repo's default branch into $base, the base a worktree starts from.
base_of() {
  local raw
  raw=$(gh api "repos/$1" 2>/dev/null </dev/null) && base=$(jq -r '.default_branch // empty' <<<"$raw") && [ -n "$base" ] \
    || sa_tooling "cannot read the default branch of $1"
}

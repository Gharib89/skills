#!/usr/bin/env bash
# The Run file: a ship run's record, outside the repo, in the session's
# scratchpad. This mechanic owns the file's shape and every flip of it, so a
# stamp is a measurement the mechanic took rather than a time a run recalled,
# and the merge summary's `Timing:` row is arithmetic rather than mental
# subtraction.
#
#   run-file init <issue|slug> --scratchpad <dir> [--tripwires <t>]
#                [--verifications <v>] [--reviewers <r>] [--legs <l>]
#   run-file open|close <n> --file <path>
#   run-file skip <n> <reason> --file <path>
#   run-file timing --file <path>
#
# Reaches no host and no repo file: the scratchpad path is the only thing it
# writes.
#
# stdout: one JSON object per call
# exit: 0 ok · 1 the mechanic's own refusal · 2 malformed invocation
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: run-file init <issue|slug> --scratchpad <dir> [--tripwires <t>] [--verifications <v>] [--reviewers <r>] [--legs <l>] | open <n> --file <path> | close <n> --file <path> | skip <n> <reason> --file <path> | timing --file <path>'
[ -n "${1:-}" ] || ship_tooling "$usage"
verb=$1; shift
case $verb in -*) ship_tooling "$usage" ;; esac

# The ten items, in the fixed wording. Four carry a tail the ship profile
# supplies; the rest are the same in every repo.
checklist() { # checklist <tripwires> <verifications> <reviewers> <legs>
  cat <<ITEMS
0 · Isolate: preflight, read the issue, worktree (or in place) on a fresh branch off the default
1 · Understand: derive success, claim, apply spec precedence
2 · Implement: classify (docs/code/infra), lane keys, TDD per class, tripwires $1
3 · Verify: $2 scoped to what changed
4 · Docs-sync + self-review: sync docs first, then \`code-review\` on the diff, auto-triage
5 · Local gate: base-fresh, then the repo's gate, all green
6 · Open PR: non-draft, Conventional-Commit title, Closes, reflect on the issue
7 · Reviewers: $3 to convergence
8 · CI: resolve any conflict, land $4 green
9 · Merge gate: hard stop for human approval (unattended: summary as PR comment, return)
ITEMS
}

# One flip, one line. The line number is the address, so the replacement is
# written whole rather than patched by a regex that could match twice.
phase_line() { grep "^- \[.\] $1 · " "$file" | head -1; }
open_phase()  { grep "^- \[.\] [0-9][0-9]* · .* in_progress ([0-9][0-9]:[0-9][0-9]→)$" "$file" \
                  | sed 's/^- \[.\] \([0-9][0-9]*\) · .*/\1/' | head -1; }
write_line() { # write_line <lineno> <replacement>
  repl=$2 awk -v ln="$1" 'NR == ln { print ENVIRON["repl"]; next } { print }' "$file" > "$file.t" \
    && mv "$file.t" "$file" || { rm -f "$file.t"; ship_tooling "cannot write $file"; }
}
lineno()  { grep -n "^- \[.\] $1 · " "$file" | head -1 | cut -d: -f1; }
# The item text: the line without its `- [ ] ` marker and without any stamp.
item()    { printf '%s' "$1" | sed 's/^- \[.\] //; s/ in_progress ([0-9][0-9]:[0-9][0-9]→)$//'; }

phase_arg() { # phase_arg <value>: the phase number, never a flag
  case ${1:-} in -*) ship_tooling "$usage" ;; esac
  case ${1:-} in '' | *[!0-9]*) ship_tooling "$usage" ;; esac
}
parse_file() { # parse_file "$@": the --file flag every flip and timing takes
  file=""
  while [ $# -gt 0 ]; do
    case $1 in
      --file) [ $# -ge 2 ] || ship_tooling "--file needs a path"; file=$2; shift 2 ;;
      *) ship_tooling "unknown flag: $1" ;;
    esac
  done
  [ -n "$file" ] || ship_tooling "$usage"
  [ -f "$file" ] || ship_fail "no Run file at $file"
}

case $verb in
init)
  [ -n "${1:-}" ] || ship_tooling "$usage"
  id=$1; shift
  case $id in -*) ship_tooling "$usage" ;; esac
  scratchpad="" tripwires=None verifications="None applicable" reviewers=none legs=None
  rebuild=false states=""
  while [ $# -gt 0 ]; do
    case $1 in
      --scratchpad)   [ $# -ge 2 ] || ship_tooling "--scratchpad needs a directory"; scratchpad=$2; shift 2 ;;
      --tripwires)    [ $# -ge 2 ] || ship_tooling "--tripwires needs a value"; tripwires=$2; shift 2 ;;
      --verifications) [ $# -ge 2 ] || ship_tooling "--verifications needs a value"; verifications=$2; shift 2 ;;
      --reviewers)    [ $# -ge 2 ] || ship_tooling "--reviewers needs a value"; reviewers=$2; shift 2 ;;
      --legs)         [ $# -ge 2 ] || ship_tooling "--legs needs a value"; legs=$2; shift 2 ;;
      --state)        [ $# -ge 2 ] || ship_tooling "--state needs <n>=<spec>"; states="$states$2
"; shift 2 ;;
      --rebuild)      rebuild=true; shift ;;
      *) ship_tooling "unknown flag: $1" ;;
    esac
  done
  [ -n "$scratchpad" ] || ship_tooling "$usage"
  dir="$scratchpad/ship-$id"
  file="$dir/run.md"
  # The rebuild path: a Run file a subagent overwrote is rebuilt in place, so
  # the guard that keeps a resumed run from wiping its own record steps aside
  # only when the caller says so.
  state_usage='--state takes <0-9>=open|done|done:<HH:MM→HH:MM>|skipped:<reason>'
  open_states=0
  while IFS= read -r st; do
    [ -n "$st" ] || continue
    case $st in
      [0-9]=open) open_states=$((open_states + 1)) ;;
      [0-9]=done | [0-9]=skipped:?*) : ;;
      [0-9]=done:[0-9][0-9]:[0-9][0-9]→[0-9][0-9]:[0-9][0-9] | [0-9]=done:[0-9][0-9]:[0-9][0-9]→[0-9][0-9]:[0-9][0-9]+1d) : ;;
      *) ship_tooling "$state_usage" ;;
    esac
  done <<EOSTATES
$states
EOSTATES
  [ "$open_states" -le 1 ] || ship_fail "a Run file holds one open phase; $open_states were given"
  [ -e "$file" ] && [ "$rebuild" = false ] && ship_fail "Run file exists: $file (pass --rebuild to rebuild it in place)"
  mkdir -p "$dir" || ship_tooling "cannot create $dir"
  items=$(checklist "$tripwires" "$verifications" "$reviewers" "$legs")
  { printf '# ship run · %s\n\n' "$id"
    printf '%s\n' "$items" | sed 's/^/- [ ] /'
    printf '\n## Design and plan\n\n(pending)\n\n## Deviations log\n\n(none yet)\n'
  } > "$file" || ship_tooling "cannot write $file"
  while IFS= read -r st; do
    [ -n "$st" ] || continue
    n=${st%%=*}; spec=${st#*=}
    line=$(phase_line "$n")
    [ -n "$line" ] || ship_fail "no phase $n line in $file"
    case $spec in
      open)      new="- [ ] $(item "$line") in_progress ($(date -u +%H:%M)→)" ;;
      done)      new="- [x] $(item "$line")" ;;
      done:*)    new="- [x] $(item "$line") (${spec#done:})" ;;
      skipped:*) new="- [x] $(item "$line") skipped (${spec#skipped:})" ;;
    esac
    write_line "$(lineno "$n")" "$new"
  done <<EOAPPLY
$states
EOAPPLY
  printf '%s\n' "$items" | jq -Rs --arg f "$file" --arg i "$id" \
    '{run_file: $f, id: $i, items: (split("\n") | map(select(. != "")))}'
  ;;
open)
  phase_arg "${1:-}"; n=$1; shift
  parse_file "$@"
  line=$(phase_line "$n")
  [ -n "$line" ] || ship_fail "no phase $n line in $file"
  busy=$(open_phase)
  if [ -n "$busy" ]; then
    [ "$busy" = "$n" ] && ship_fail "phase $n is already open"
    ship_fail "phase $busy is open; close it before opening $n"
  fi
  new="- [ ] $(item "$line") in_progress ($(date -u +%H:%M)→)"
  write_line "$(lineno "$n")" "$new"
  jq -n --arg f "$file" --argjson n "$n" --arg l "$new" \
    '{run_file: $f, phase: $n, state: "open", line: $l, mirror: "in_progress"}'
  ;;
close)
  phase_arg "${1:-}"; n=$1; shift
  parse_file "$@"
  line=$(phase_line "$n")
  [ -n "$line" ] || ship_fail "no phase $n line in $file"
  case $line in
    *" in_progress ("??:??"→)") : ;;
    *) ship_fail "phase $n is not open" ;;
  esac
  start=${line##*in_progress (}
  start=${start%%→*}
  end=$(date -u +%H:%M)
  # A close stamped before its open crossed midnight UTC; the range still reads
  # left to right, and `timing` adds the day.
  [ "$end" \< "$start" ] && end="$end+1d"
  new="- [x] $(item "$line") ($start→$end)"
  write_line "$(lineno "$n")" "$new"
  jq -n --arg f "$file" --argjson n "$n" --arg l "$new" \
    '{run_file: $f, phase: $n, state: "closed", line: $l, mirror: "completed"}'
  ;;
skip)
  phase_arg "${1:-}"; n=$1; shift
  [ -n "${1:-}" ] || ship_tooling "$usage"
  reason=$1; shift
  case $reason in -*) ship_tooling "$usage" ;; esac
  parse_file "$@"
  line=$(phase_line "$n")
  [ -n "$line" ] || ship_fail "no phase $n line in $file"
  case $line in
    *" in_progress ("??:??"→)") ship_fail "phase $n is open; close it before skipping it" ;;
  esac
  new="- [x] $(item "$line") skipped ($reason)"
  write_line "$(lineno "$n")" "$new"
  jq -n --arg f "$file" --argjson n "$n" --arg l "$new" --arg r "$reason" \
    '{run_file: $f, phase: $n, state: "skipped", reason: $r, line: $l, mirror: "completed"}'
  ;;
timing)
  parse_file "$@"
  # Every range on every phase line, in minutes. A `+1d` close crossed midnight
  # UTC, so it carries the day; an aggregate whose end lands before its start
  # crossed one too. Times are read by splitting on the arrow rather than by
  # offset, because it is one character to gawk and three bytes to mawk.
  awk '
    function mins(t,   hm) { split(t, hm, ":"); return hm[1] * 60 + hm[2] }
    function agg(a, b) { return (b < a) ? b + 1440 - a : b - a }
    /^- \[.\] [0-9][0-9]* · / {
      p = substr($0, 7); sub(/ .*/, "", p)
      rest = $0; total = 0; found = 0
      while (match(rest, /\([0-9][0-9]:[0-9][0-9]→[0-9][0-9]:[0-9][0-9](\+1d)?\)/)) {
        r = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        split(r, part, "→")
        st = part[1]; sub(/^\(/, "", st)
        en = part[2]; day = (en ~ /\+1d/) ? 1440 : 0
        sub(/\+1d/, "", en); sub(/\)$/, "", en)
        total += mins(en) + day - mins(st)
        if (!found) { first[p] = mins(st); found = 1 }
        last[p] = mins(en) + day
      }
      if (found) { phase[p] = total } else { phase[p] = "unverified" }
      seen[p] = 1
    }
    END {
      for (p in seen) printf "phase\t%s\t%s\n", p, phase[p]
      stp = (0 in first && 6 in last) ? agg(first[0], last[6]) : "unverified"
      ptg = (6 in last && 8 in last) ? agg(last[6], last[8]) : "unverified"
      printf "agg\tstart_to_pr\t%s\n", stp
      printf "agg\tpr_to_gate\t%s\n", ptg
    }
  ' "$file" | jq -Rs --arg f "$file" '
    def num: if . == "unverified" then . else tonumber end;
    def m: if . == "unverified" then . else tostring + "m" end;
    [split("\n")[] | select(. != "") | split("\t")] as $rows
    | ($rows | map(select(.[0] == "phase") | {(.[1]): (.[2] | num)}) | add // {}) as $phases
    | ($rows | map(select(.[0] == "agg") | {(.[1]): (.[2] | num)}) | add) as $agg
    | {run_file: $f, start_to_pr: $agg.start_to_pr, pr_to_gate: $agg.pr_to_gate, phases: $phases,
       row: ("start→PR \($agg.start_to_pr | m) · PR→gate \($agg.pr_to_gate | m) · per phase: "
             + ([range(0; 9) | "\(.) \($phases[tostring] // "unverified")"] | join(" · ")))}'
  ;;
*)
  ship_tooling "$usage"
  ;;
esac

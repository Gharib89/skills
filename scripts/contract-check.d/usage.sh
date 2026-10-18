# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # variables set by the sourcing script
# Checks 11 to 13 of scripts/contract-check.sh, sourced by it: they share its variables.
# Checks 11 to 14 share a reading of the usage line. A mechanic whose --help
# check 5 reported has no line saved and is skipped here, so one fault is one
# report. `tail_of` drops the name; `usage_alts` splits what is left at the
# top-level ` | `, a ` | ` inside [...] or (...) belonging to its group.
tail_of() { local t=${2#"usage: $1"}; printf '%s' "${t# }"; }
usage_alts() {
  printf '%s\n' "$1" | awk '{
    d = 0; cur = ""; n = length($0)
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)
      if (c == "[" || c == "(") d++
      else if (c == "]" || c == ")") d--
      if (d == 0 && substr($0, i, 3) == " | ") { print cur; cur = ""; i += 2; continue }
      cur = cur c
    }
    print cur }'
}
# lead_slots <text>: the <slots> before the first token starting with [, ( or -.
lead_slots() {
  local t out=""
  set -f
  for t in $1; do
    case $t in '['*|'('*|-*) break ;; '<'*) out="$out $t" ;; esac
  done
  set +f
  printf '%s' "${out# }"
}
# call_slots <text>: the positionals of a valid call, one per line: literal
# words kept (a verb), an id as 1, <type> as fix, any other <slot> as x. A
# token ending in a comma ends the slots, so prose after a verb is not one.
call_slots() {
  local t lit
  set -f
  for t in $1; do
    case $t in '['*|'('*|-*|'"'*) break ;; esac
    case $t in
      '<issue>'|'<pr>'|'<n>'|'<issue|none>') echo 1 ;;
      '<type>') echo fix ;;
      '<'*) echo x ;;
      *) lit=${t%,}; echo "${lit%%|*}" ;;
    esac
    case $t in *,) break ;; esac
  done
  set +f
}
# flags_of <text>: the sorted, space-joined set of --flags in the text.
flags_of() { printf '%s\n' "$1" | grep -oE -e '--[a-z][a-z-]*' | sort -u | tr '\n' ' ' | sed 's/ $//'; }
# required_flags <usage tail>: one line per flag the call must carry, the flags
# of a `( --a <x> | --b )` group joined by `|` (one of them), anything inside
# [...] left out.
required_flags() {
  printf '%s\n' "$1" | awk '
    function flags(str, sep,   r) {
      r = ""
      while (match(str, /--[a-z][a-z-]*/)) { r = r (r == "" ? "" : sep) substr(str, RSTART, RLENGTH); str = substr(str, RSTART + RLENGTH) }
      return r
    }
    { d = 0; g = 0; top = ""; grp = ""; n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (c == "[") { d++; continue }
        if (c == "]") { d--; continue }
        if (d > 0) continue
        if (c == "(") { g = 1; grp = ""; continue }
        if (c == ")") { g = 0; print flags(grp, "|"); continue }
        if (g) grp = grp c; else top = top c
      }
      n = split(flags(top, " "), f, " ")
      for (i = 1; i <= n; i++) print f[i] }'
}

# flag_value <flag>: a value that passes the flag's own guard, for a call that
# must get past the flags and fail somewhere else.
flag_value() {
  case $1 in
    --body-file) printf '%s' "$work/body.md" ;; --title) printf 'fix: x' ;; --label) printf 'needs-triage' ;;
    --reviewer) printf 'copilot' ;; --section) printf 'Review' ;; --scratchpad) printf '%s' "$work" ;; *) printf 'x' ;;
  esac
}
# call_args <alt> [<flag>]: sets `args` to a valid call of the alternative, its
# positionals and every required flag with a valid value, leaving out the
# requirement <flag> belongs to. Check 12 gives <flag> its own bad value after
# these: with the others missing, a guard that admits the bad value is hidden
# behind the usage line the missing flag earns.
call_args() {
  local alt=$1 skip=${2:-} a r f
  args=()
  while IFS= read -r a; do [ -z "$a" ] || args+=("$a"); done <<EOP
$(call_slots "$alt")
EOP
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    if [ -n "$skip" ]; then case "|$r|" in *"|$skip|"*) continue ;; esac; fi
    f=${r%%|*}
    case $alt in
      *"$f <"*|*"$f \"<"*) args+=("$f" "$(flag_value "$f")") ;;
      *) args+=("$f") ;;
    esac
  done <<EOR
$(required_flags "$alt")
EOR
}

printf 'readable body\n' > "$work/body.md" || { echo "cannot create a temp file" >&2; exit 2; }

# 11. The header synopsis agrees with the usage line. The header is what a
# maintainer reads and the usage line is what a run reads, and they were typed
# apart: `open-pr` documented `<issue>` for a slot that also takes `none`, and
# `run-file` named `<where>` where the flags are. Compared as two sets: the
# --flags, over the synopsis block (the header lines from the first one opening
# with the mechanic's name to the next line that is exactly `#`) and the usage
# line, and the leading <slots>, over the block's first line and the usage line.
# A mechanic with no synopsis block is a stub with no header to compare.
for path in "$dir"/*.sh; do
  m=$(basename "$path" .sh)
  [ -f "$work/$m.usage" ] || continue
  block=$(awk -v m="$m" '$0 ~ "^#   " m "( |$)" { on = 1 } on && $0 == "#" { exit } on { print }' "$path")
  [ -n "$block" ] || continue
  usage=$(cat "$work/$m.usage"); utail=$(tail_of "$m" "$usage")
  first=$(printf '%s\n' "$block" | head -1); first=${first#"#   $m"}
  hf=$(flags_of "$block"); uf=$(flags_of "$utail")
  hs=$(lead_slots "$first"); us=$(lead_slots "$utail")
  diff=""
  [ "$hf" = "$uf" ] || diff="flags (header: ${hf:-none}; usage: ${uf:-none})"
  [ "$hs" = "$us" ] || diff="${diff:+$diff; }leading slots (header: ${hs:-none}; usage: ${us:-none})"
  [ -z "$diff" ] || { printf '%s: header synopsis and --help usage line disagree: %s\n' "$m" "$diff"; rc=1; }
done

# 12. Every flag that takes a value refuses a leading-dash one, with the usage
# line and exit 2. A guard that tests only for an empty value reads the next
# flag as the value: `open-pr --title --body-file b.md` took `--body-file` as
# the title. The flags are the usage line's `--flag <value>` pairs; the call
# gives the flag the positionals of the first alternative that names it, so a
# verb mechanic sees a verb it knows, and `--x` as its value.
for path in "$dir"/*.sh; do
  m=$(basename "$path" .sh)
  [ -f "$work/$m.usage" ] || continue
  apath=$(cd "$(dirname "$path")" && pwd)/$(basename "$path")
  usage=$(cat "$work/$m.usage"); utail=$(tail_of "$m" "$usage")
  # A variadic flag (`--carry <file>...`) ends its list at the next flag, so a
  # dash-led token after it is a flag, never its value.
  variadic=$(printf '%s\n' "$utail" | grep -oE -e '--[a-z][a-z-]* "?<[^ ]*>\.\.\.' | sed 's/ .*//')
  for f in $(printf '%s\n' "$utail" | grep -oE -e '--[a-z][a-z-]* "?<' | sed 's/ .*//' | sort -u); do
    case " $(echo $variadic) " in *" $f "*) continue ;; esac
    alt=$utail
    while IFS= read -r a; do
      case $a in *"$f <"*|*"$f \"<"*) alt=$a; break ;; esac
    done <<EOA
$(usage_alts "$utail")
EOA
    call_args "$alt" "$f"
    out=$(cd "$nogit" && bash "$apath" ${args[@]+"${args[@]}"} "$f" --x 2>/dev/null); st=$?
    if [ "$st" -ne 2 ] || ! printf '%s' "$out" | jq -se --arg u "$usage" 'length == 1 and (.[0] | type == "object" and .error == $u)' >/dev/null 2>&1; then
      printf '%s: %s took a leading-dash value; guard it with ship_flag_value so it answers the usage line and exit 2\n' "$m" "$f"
      rc=1
    fi
  done
done

# 13. A host failure prints exactly one JSON object. Each mechanic that loads a
# host adapter is run against the Host fake with every host function failing,
# from a throwaway checkout whose origin names GitHub, and what it prints on
# stdout has to be one object whatever its exit code: a run reads the answer
# with jq, and an exit path that prints nothing or two objects reads as a
# different failure than the one that happened. The call is a valid one (its
# positionals, and every required flag with a value that passes its guard), so
# the failure reached is the host's. `gh` and `az` stubs exit 127 and git may
# speak only `file:`, so nothing leaves the machine. A tree without the fake has
# nothing to drive.
fake=$(dirname "$0")/../tests/host-fake.sh
if [ -f "$fake" ]; then
  fake=$(cd "$(dirname "$fake")" && pwd)/host-fake.sh
  root=$(cd "$(dirname "$0")/.." && pwd)
  # The function list is the fake's own, so a host function added there is
  # failed here without this file learning of it.
  fns=$(sed -n '/^for _fn in/,/; do$/p' "$fake" | tr -s ' \\' '\n\n' | tr -d ';' | grep '^host_')
  [ -n "$fns" ] || { printf '%s: no host_* function on its `for _fn in` line; check 13 has nothing to fail\n' "$fake"; rc=1; }
  mkdir -p "$work/bin"
  for cli in gh az; do printf '#!/bin/sh\nexit 127\n' > "$work/bin/$cli"; chmod +x "$work/bin/$cli"; done
  for path in "$dir"/*.sh; do
    [ -n "$fns" ] || break
    m=$(basename "$path" .sh)
    [ -f "$work/$m.usage" ] || continue
    grep -q 'ship_load_host' "$path" || continue
    apath=$(cd "$(dirname "$path")" && pwd)/$(basename "$path")
    usage=$(cat "$work/$m.usage"); utail=$(tail_of "$m" "$usage")
    alt=$(usage_alts "$utail" | head -1)
    call_args "$alt"
    # A wait mechanic retries a failing host once per interval: at ci-wait's and
    # poll-pr's defaults this check slept 100 s, once per gate.
    case $utail in *'[--interval <s>]'*) args+=(--interval 1) ;; esac
    repo=$(mktemp -d "$work/repo.XXXXXX") && sf=$(mktemp -d "$work/fake.XXXXXX") || { echo "cannot create a temp directory" >&2; exit 2; }
    for fn in $fns; do : > "$sf/$fn.1.fail"; done
    mkdir -p "$repo/docs/agents" "$repo/.github"
    cp "$root/docs/agents/ship.md" "$repo/docs/agents/" || { printf '%s: check 13 setup failed: cannot copy docs/agents/ship.md\n' "$m"; rc=1; continue; }
    cp "$root/.github/pull_request_template.md" "$repo/.github/" || { printf '%s: check 13 setup failed: cannot copy .github/pull_request_template.md\n' "$m"; rc=1; continue; }
    ( cd "$repo" && git init -q . && git remote add origin https://github.com/o/r.git \
        && git -c user.name=gate -c user.email=gate@example.com -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q --allow-empty -m init ) >/dev/null 2>&1 \
      || { printf '%s: check 13 setup failed: cannot git init the throwaway checkout\n' "$m"; rc=1; continue; }
    out=$(cd "$repo" && PATH="$work/bin:$PATH" SHIP_HOST_ADAPTER=$fake SHIP_FAKE=$sf GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0 \
      bash "$apath" ${args[@]+"${args[@]}"} 2>/dev/null </dev/null)
    if ! printf '%s' "$out" | jq -se 'length == 1 and (.[0] | type == "object")' >/dev/null 2>&1; then
      n="$(printf '%s' "$out" | jq -s length 2>/dev/null) JSON values" || n="unparseable output"
      call=$m; [ "${#args[@]}" -eq 0 ] || call="$m ${args[*]}"
      printf '%s: with every host_* failing in the Host fake, `%s` printed %s on stdout; want exactly one object\n' "$m" "$call" "$n"
      rc=1
    fi
  done
fi


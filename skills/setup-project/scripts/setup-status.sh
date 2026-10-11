#!/usr/bin/env bash
# The setup status: one JSON line per project-setup step, in fixed order, read
# from what each step leaves behind. It reads local files, git and the local
# answers of the tools it lists (`--version`, `gh auth token`,
# `az account show`), and never a host: the source repo's lock comes in as a
# file `source-lock.sh` fetched, so the same tree always gives the same table.
#
#   setup-status <root> [<source-lock>]
#
# A row's state is `run` (what the step leaves is missing: its first run),
# `re-run audit` (present but behind: the step's re-run audit) or `done`. The
# proof row is always `run`: it is settled by Ship's preflight at the run's end.
# Without a source lock, chain skill versions are not compared.
#
# stdout: one {step, state, evidence[]} per line, the steps `tools`,
#   `repo-and-remote`, `installed-skills`, `matts-setup`, `harness`,
#   `ships-setup`, `proof`; or one {error} on a tooling failure
# exit: 0 the rows printed · 2 usage, a root that is no directory, jq missing,
#   setup-project's own `composes:` line unreadable, or a source lock that is
#   unreadable, not a lock or carries a version that is no dotted number
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: setup-status <root> [<source-lock>]'
sp_help "$usage" "$@"
command -v jq >/dev/null || sp_tooling 'jq not installed'
case ${1:-} in ''|-*) sp_tooling "$usage" ;; esac
root=$1
[ -d "$root" ] || sp_tooling "not a directory: $root"
slock=${2:-}
if [ -n "$slock" ]; then
  jq -e '(.skills | type == "object")
    and ([.skills[] | .version // empty | test("^[0-9]+(\\.[0-9]+)*$")] | all)' "$slock" >/dev/null 2>&1 \
    || sp_tooling "source lock unreadable or malformed: $slock"
fi
self=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd) || sp_tooling 'cannot find SKILL.md'
own=$(sp_front "$self/SKILL.md" composes)
[ -n "$own" ] || sp_tooling "cannot read the composes line of $self/SKILL.md"

ev=()
row() { # <step> <state>: prints the row with the evidence in $ev, then clears it
  jq -cn --arg s "$1" --arg t "$2" '{step: $s, state: $t, evidence: $ARGS.positional}' --args ${ev[@]+"${ev[@]}"}
  ev=()
}
front() { [ -f "$1" ] && sp_front "$1" "$2"; }
ver() { "$@" 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n 1; }
# <a> <b>: 0 when dotted number a is lower than b.
version_lt() { awk -v a="$1" -v b="$2" 'BEGIN { n = split(a, x, "."); m = split(b, y, "."); if (m > n) n = m
  for (i = 1; i <= n; i++) { if (x[i] + 0 < y[i] + 0) exit 0; if (x[i] + 0 > y[i] + 0) exit 1 }; exit 1 }'; }

origin=''
isgit=''
if [ -e "$root/.git" ]; then isgit=1; origin=$(git -C "$root" remote get-url origin 2>/dev/null); fi
manifest='' tool=''
for m in pyproject.toml package.json Cargo.toml go.mod; do [ -f "$root/$m" ] && { manifest=$m; break; }; done
if [ -z "$manifest" ]; then
  for m in "$root"/*.sln "$root"/*.csproj "$root"/*.fsproj; do [ -f "$m" ] && { manifest=${m##*/}; break; }; done
fi
case $manifest in
  pyproject.toml) tool=uv ;; Cargo.toml) tool=cargo ;; go.mod) tool=go ;; '') ;;
  package.json)
    if [ -f "$root/pnpm-lock.yaml" ]; then tool=pnpm
    elif [ -f "$root/bun.lock" ] || [ -f "$root/bun.lockb" ]; then tool=bun; fi ;;
  *) tool=dotnet ;;
esac

# Tools.
state='done'
for t in git jq node npx $tool; do
  v=''; [ "$t" = go ] && v=$(ver go version) || v=$(ver "$t" --version)
  if command -v "$t" >/dev/null; then ev+=("$t ${v:-version unreadable}"); else ev+=("$t missing"); state=run; fi
done
case $origin in
  *dev.azure.com*|*visualstudio.com*)
    if ! command -v az >/dev/null; then ev+=("az missing"); state=run
    elif az account show >/dev/null 2>&1; then ev+=("az signed in")
    else ev+=("az signed out"); state=run; fi ;;
  *)
    if ! command -v gh >/dev/null; then ev+=("gh missing"); state=run
    elif gh auth token >/dev/null 2>&1; then ev+=("gh $(ver gh --version) signed in")
    else ev+=("gh signed out"); state=run; fi ;;
esac
row tools "$state"

# Repo and remote. A stack manifest is needed only by a repo with no commits:
# one with history already has whatever stack it has.
state='done'
if [ -n "$isgit" ]; then ev+=(".git present"); else ev+=("no .git"); state=run; fi
if [ -n "$origin" ]; then ev+=("origin $origin"); else ev+=("no origin remote"); state=run; fi
if [ -n "$manifest" ]; then ev+=("manifest $manifest")
elif [ -n "$isgit" ] && git -C "$root" rev-parse -q --verify HEAD >/dev/null; then ev+=("no stack manifest, history present")
else ev+=("no stack manifest"); state=run; fi
row repo-and-remote "$state"

# Installed skills: the chain set at project scope, each in the lock and on disk.
lock=$root/skills-lock.json
jq -e '.skills | type == "object"' "$lock" >/dev/null 2>&1 || lock=''
entry() { [ -n "$lock" ] && jq -r --arg k "$1" '.skills[$k] // empty | "\(.source // "")#\(.ref // "none")"' "$lock"; }
state='done'
[ -n "$slock" ] || ev+=("versions not compared: no source lock")
pins=$own
for s in ship cloud-ship setup-skills update-skills setup-harness; do
  e=$(entry "$s")
  if [ -z "$e" ] || [ ! -d "$root/.claude/skills/$s" ]; then ev+=("$s missing"); state=run; continue; fi
  # Only the source repo's copy is the chain skill; `.` is the source repo itself.
  src=${e%#*}
  ours=''; shopt -s nocasematch; [[ $src == gharib89/skills || $src == . ]] && ours=1; shopt -u nocasematch
  if [ -z "$ours" ]; then ev+=("$s from $src, not Gharib89/skills"); state=run; continue; fi
  pins="$pins $(front "$root/.claude/skills/$s/SKILL.md" composes)"
  v=$(front "$root/.claude/skills/$s/SKILL.md" version)
  want=''; [ -n "$slock" ] && want=$(jq -r --arg k "$s" '.skills[$k].version // empty' "$slock")
  if [ -z "$v" ]; then ev+=("$s version unreadable"); [ "$state" = run ] || state='re-run audit'
  elif [ -n "$want" ] && version_lt "$v" "$want"; then ev+=("$s $v behind $want"); [ "$state" = run ] || state='re-run audit'
  else ev+=("$s $v"); fi
done
for p in $pins; do
  s=${p##*:}; pin=${p%:*}
  e=$(entry "$s")
  if [ -z "$e" ] || [ ! -d "$root/.claude/skills/$s" ]; then ev+=("$s missing"); state=run
  elif [ "$e" != "$pin" ]; then ev+=("$s at $e, pinned $pin"); [ "$state" = run ] || state='re-run audit'
  else ev+=("$s pinned"); fi
done
row installed-skills "$state"

# Matt's setup: the three parent docs.
state='done'
for f in issue-tracker triage-labels domain; do
  if [ -f "$root/docs/agents/$f.md" ]; then ev+=("docs/agents/$f.md present"); else ev+=("docs/agents/$f.md missing"); state=run; fi
done
row matts-setup "$state"

# <step> <profile> <skill> <schema key>: a profile, its `Schema:` against the
# schema the installed skill reads.
profile() {
  local have want
  if [ ! -f "$root/$2" ]; then ev+=("$2 missing"); row "$1" run; return; fi
  have=$(sed -n 's/^Schema: \([0-9][0-9]*\)$/\1/p' "$root/$2" | head -n 1)
  want=$(front "$root/.claude/skills/$3/SKILL.md" "$4")
  ev+=("$2 Schema ${have:-unreadable}, $3 reads ${want:-unknown}")
  if [ -n "$have" ] && [ "$have" = "$want" ]; then row "$1" 'done'; else row "$1" 're-run audit'; fi
}
profile harness docs/agents/harness.md setup-harness harness-schema
profile ships-setup docs/agents/ship.md ship profile-schema

ev=("read at the run's end: .claude/skills/ship/scripts/preflight.sh none")
row proof run

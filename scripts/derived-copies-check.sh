#!/usr/bin/env bash
# This repo is both the source of the shared skills and a consumer of them, so
# `.claude/skills/<n>` must be the bytes of `skills/<n>`. A change to a skill
# that was not followed by the refresh line fails here. The `derived-copies`
# gate in scripts/local-gate.sh and `scripts/check.sh full` run this.
#
# The set of skills this repo writes is read from the lock's `source: "."`
# entries, and this script hardcodes none. Every other place that names the set
# must agree: each `skills/<n>/` is in the set, each skill in the set has a
# source, a derived copy and a `.release/<n>.toml`, and the release workflow's
# `SKILLS` list and its release-commit conditions name the set exactly.
# Vendored entries are ignored.
#
#   scripts/derived-copies-check.sh [<root>]    <root> defaults to this repo
#
# stdout: one line per difference
# exit: 0 identical · 1 a difference · 2 tooling
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 2
root=${1:-$here/..}
cd "$root" || exit 2
[ -f skills-lock.json ] || { echo 'cannot read skills-lock.json' >&2; exit 2; }
skills=$(jq -r '.skills | to_entries[] | select(.value.source == ".") | .key' skills-lock.json | sort) \
  || { echo 'cannot parse skills-lock.json' >&2; exit 2; }

rc=0
for d in skills/*/; do
  [ -d "$d" ] || continue
  s=${d#skills/}; s=${s%/}
  grep -qxF "$s" <<<"$skills" || { echo "skills/$s is not a source \".\" entry in skills-lock.json; add --skill $s to the refresh line and run it"; rc=1; }
done
for s in $skills; do
  [ -f ".release/$s.toml" ] || { echo "missing release configuration: .release/$s.toml"; rc=1; }
  [ -d "skills/$s" ] || { echo "missing source: skills/$s"; rc=1; continue; }
  [ -d ".claude/skills/$s" ] || { echo "missing derived copy: .claude/skills/$s"; rc=1; continue; }
  diff -rq "skills/$s" ".claude/skills/$s" || rc=1
  # diff -rq compares content only. A mechanic that loses its executable bit
  # on one side passes that check and then fails at run time, so compare the
  # set of executable files too.
  diff <(cd "skills/$s" && find . -type f -perm -u+x | sort) \
       <(cd ".claude/skills/$s" && find . -type f -perm -u+x | sort) \
    || { echo "executable bits differ between skills/$s and .claude/skills/$s"; rc=1; }
done

# The workflow keeps its literal list, since a job's `if:` cannot read a file;
# this holds both of its copies to the lock, reading only the `SKILLS:` key and
# the `startsWith` lines, so a subject quoted in a comment is no condition.
wf=.github/workflows/semantic-release.yml
[ -f "$wf" ] || { echo "cannot read $wf" >&2; exit 2; }
want=$(tr '\n' ' ' <<<"$skills"); want=${want% }
got=$(sed -n 's/^ *SKILLS: //p' "$wf" | tr ' ' '\n' | sort | tr '\n' ' ') \
  || { echo "cannot read $wf" >&2; exit 2; }
got=${got% }
[ "$got" = "$want" ] || { echo "$wf SKILLS names $got, the lock's set is $want"; rc=1; }
got=$(sed -n "s/^[ &|(]*startsWith(github.event.head_commit.message, 'chore(release): \([^ ]*\) v').*/\1/p" "$wf" | sort | tr '\n' ' ') \
  || { echo "cannot read $wf" >&2; exit 2; }
got=${got% }
[ "$got" = "$want" ] || { echo "$wf release-commit conditions name $got, the lock's set is $want"; rc=1; }

# The profile schema number across its three files: scripts/profile-schema-check.sh.
"$here/profile-schema-check.sh" . || rc=1
# Every pinned ref a skill states against the lock's: scripts/pin-check.sh.
"$here/pin-check.sh" . || rc=1
exit $rc

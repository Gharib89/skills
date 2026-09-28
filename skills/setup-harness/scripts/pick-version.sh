#!/usr/bin/env bash
# The catalog's version rule: the newest non-prerelease whose registry publish
# time is at least 7 days old, so a just-published compromised release never
# lands. Newest by version order, not publish order. A yanked PyPI release is
# passed over. apt is exempt (its versions are the distribution's) and takes
# no call here.
#
#   pick-version.sh <npm|pypi|go> <name>
#
# <name> is the package name, or for go the package path `go install` takes;
# its module is found by asking the proxy for each prefix in turn. crates and
# nuget, which the catalog's pin vocabulary names, arrive with their stacks'
# entries.
#
# stdout: the version
# exit: 0 picked · 1 no release qualifies · 2 usage or registry unreachable
set -uo pipefail
usage="usage: pick-version.sh <npm|pypi|go> <name>"
case ${1:-} in
  -h | --help) echo "$usage"; exit 0 ;;
  npm | pypi | go) [ -n "${2:-}" ] || { echo "$usage" >&2; exit 2; } ;;
  *) echo "$usage" >&2; exit 2 ;;
esac
registry=$1 name=$2
fetch() { curl -fsSL --max-time 30 "$1"; }

# stdin: one `<version> <iso time>` line per release; prints the pick.
choose() {
  python3 -c '
import datetime, re, sys
cut = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=7)
best = None
for line in sys.stdin:
    parts = line.split()
    if len(parts) != 2:
        continue  # a release the registry gives no publish time
    v, t = parts
    if not re.fullmatch(r"v?\d+(\.\d+)*", v):
        continue  # a prerelease or a local version
    if datetime.datetime.fromisoformat(t.replace("Z", "+00:00")) > cut:
        continue
    key = tuple(int(p) for p in v.lstrip("v").split("."))
    if best is None or key > best[0]:
        best = (key, v)
if best is None:
    sys.exit(1)
print(best[1])'
}

case $registry in
  npm)
    json=$(fetch "https://registry.npmjs.org/$name") || exit 2
    printf '%s' "$json" | python3 -c '
import json, sys
for v, t in json.load(sys.stdin)["time"].items():
    if v not in ("created", "modified"):
        print(v, t)' | choose ;;
  pypi)
    json=$(fetch "https://pypi.org/pypi/$name/json") || exit 2
    printf '%s' "$json" | python3 -c '
import json, sys
for v, files in json.load(sys.stdin)["releases"].items():
    if files and not any(f.get("yanked") for f in files):
        print(v, min(f["upload_time_iso_8601"] for f in files))' | choose ;;
  go)
    mod=$name list=''
    while :; do
      list=$(fetch "https://proxy.golang.org/$mod/@v/list" 2>/dev/null) && [ -n "$list" ] && break
      case $mod in */*) mod=${mod%/*} ;; *) exit 2 ;; esac
    done
    for v in $list; do
      case $v in *-*) continue ;; esac
      info=$(fetch "https://proxy.golang.org/$mod/@v/$v.info") || exit 2
      printf '%s %s\n' "$v" "$(printf '%s' "$info" | sed -n 's/.*"Time":"\([^"]*\)".*/\1/p')"
    done | choose ;;
esac

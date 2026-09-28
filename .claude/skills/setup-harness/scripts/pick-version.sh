#!/usr/bin/env bash
# The install check's version choice: the newest non-prerelease whose registry publish
# time is at least 7 days old, so a just-published compromised release never
# lands. Newest by version order, not publish order. A yanked PyPI release is
# passed over. apt is exempt (its versions are the distribution's) and takes
# no call here.
#
#   pick-version.sh <npm|pypi|go|crates|nuget|maven|dockerhub> <name>
#
# <name> is the package name; for go the package path `go install` takes, its module
# found by asking the proxy for each prefix in turn; for maven `<group>:<artifact>` on
# Maven Central; for dockerhub the image repository. A yanked crate and an unlisted
# NuGet release are passed over as a yanked PyPI release is. For maven the publish
# time is the release pom's Last-Modified; for dockerhub it is the tag's last push,
# so a re-pushed tag counts from its re-push.
#
# stdout: the version
# exit: 0 picked · 1 no release qualifies · 2 usage or registry unreachable
set -uo pipefail
usage="usage: pick-version.sh <npm|pypi|go|crates|nuget|maven|dockerhub> <name>"
case ${1:-} in
  -h | --help) echo "$usage"; exit 0 ;;
  npm | pypi | go | crates | nuget | maven | dockerhub) [ -n "${2:-}" ] || { echo "$usage" >&2; exit 2; } ;;
  *) echo "$usage" >&2; exit 2 ;;
esac
registry=$1 name=$2
# crates.io refuses a request without a User-Agent naming its sender. Maven
# Central's Cloudflare front answers about one request in four from a cloud
# session 429, in bursts (measured), so a retry waits 5 s rather than curl's 1 s.
fetch() { curl -fsSL --compressed --retry 6 --retry-delay 5 --max-time 30 -A 'setup-harness pick-version (https://github.com/Gharib89/skills)' "$1"; }

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
  crates)
    url="https://crates.io/api/v1/crates/$name/versions?per_page=100"
    # Collected before choosing, so a page that fails exits 2 with no pick.
    lines=$(while [ -n "$url" ]; do
      json=$(fetch "$url") || exit 2
      printf '%s' "$json" | python3 -c '
import json, sys
for v in json.load(sys.stdin)["versions"]:
    if not v["yanked"]:
        print(v["num"], v["created_at"])'
      next=$(printf '%s' "$json" | python3 -c 'import json, sys; print(json.load(sys.stdin)["meta"]["next_page"] or "")')
      url=${next:+https://crates.io/api/v1/crates/$name/versions$next}
    done) || exit 2
    printf '%s\n' "$lines" | choose ;;
  nuget)
    # The index inlines small registration pages and links the rest by @id; a
    # linked page's own items are the releases.
    releases() {
      python3 -c '
import json, sys
for item in json.load(sys.stdin)["items"]:
    for leaf in item.get("items", [item] if "catalogEntry" in item else []):
        e = leaf["catalogEntry"]
        if e.get("listed", True):
            print(e["version"], e["published"])'
    }
    # The gz-semver2 hive is the only one listing SemVer 2.0 releases.
    index=$(fetch "https://api.nuget.org/v3/registration5-gz-semver2/$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')/index.json") || exit 2
    pages=$(printf '%s' "$index" | python3 -c '
import json, sys
for p in json.load(sys.stdin)["items"]:
    if "items" not in p:
        print(p["@id"])')
    lines=$(printf '%s' "$index" | releases
      for page in $pages; do
        json=$(fetch "$page") || exit 2
        printf '%s' "$json" | releases
      done) || exit 2
    printf '%s\n' "$lines" | choose ;;
  maven)
    base="https://repo1.maven.org/maven2/$(printf '%s' "${name%%:*}" | tr . /)/${name#*:}"
    xml=$(fetch "$base/maven-metadata.xml") || exit 2
    # Central dates a release only by its files' Last-Modified, one request per
    # version, so walk newest first and stop at the first old enough.
    lines=$(printf '%s' "$xml" | grep -o '<version>[^<]*</version>' | sed 's/<[^>]*>//g' | python3 -c '
import re, sys
vs = [v.strip() for v in sys.stdin if re.fullmatch(r"\d+(\.\d+)*", v.strip())]
print("\n".join(sorted(vs, key=lambda v: tuple(int(p) for p in v.split(".")), reverse=True)))' |
      while IFS= read -r v; do
        mod=$(curl -fsSI --retry 6 --retry-delay 5 --max-time 30 "$base/$v/${name#*:}-$v.pom" | tr -d '\r' | sed -n 's/^[Ll]ast-[Mm]odified: *//p') || exit 2
        line=$(python3 -c 'import email.utils, sys; print(sys.argv[1], email.utils.parsedate_to_datetime(sys.argv[2]).isoformat())' "$v" "$mod") || exit 2
        printf '%s\n' "$line"
        printf '%s\n' "$line" | choose >/dev/null && break
      done) || exit 2
    printf '%s\n' "$lines" | choose ;;
  dockerhub)
    url="https://hub.docker.com/v2/repositories/$name/tags?page_size=100"
    lines=$(while [ -n "$url" ]; do
      json=$(fetch "$url") || exit 2
      printf '%s' "$json" | python3 -c '
import json, sys
for t in json.load(sys.stdin)["results"]:
    if t["tag_last_pushed"]:
        print(t["name"], t["tag_last_pushed"])'
      url=$(printf '%s' "$json" | python3 -c 'import json, sys; print(json.load(sys.stdin)["next"] or "")')
    done) || exit 2
    printf '%s\n' "$lines" | choose ;;
esac

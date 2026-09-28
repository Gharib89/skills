#!/usr/bin/env bash
# skills/setup-harness/scripts/pick-version.sh: the catalog's version rule, the
# newest non-prerelease published at least 7 days ago. The subject is the
# version it prints per registry. A fake `curl` in front of PATH answers each
# registry URL with a fixture whose publish times are relative to now, so the
# 7-day line sits between two releases.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
script=$PWD/skills/setup-harness/scripts/pick-version.sh
iso() { python3 -c "import datetime,sys; print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(days=int(sys.argv[1]))).strftime('%Y-%m-%dT%H:%M:%S.000Z'))" "$1"; }
d30=$(iso 30) d10=$(iso 10) d3=$(iso 3)

mkdir -p "$fixture/bin" "$fixture/r"
cat > "$fixture/bin/curl" <<FAKE
#!/bin/sh
for a; do url=\$a; done
case \$url in
  https://registry.npmjs.org/prettier) cat "$fixture/r/npm" ;;
  https://pypi.org/pypi/ruff/json) cat "$fixture/r/pypi" ;;
  https://proxy.golang.org/mvdan.cc/sh/v3/@v/list) printf 'v3.9.0\nv3.10.0\nv3.11.0-rc1\nv3.11.0\n' ;;
  https://proxy.golang.org/mvdan.cc/sh/v3/@v/v3.11.0.info) printf '{"Version":"v3.11.0","Time":"$d3"}' ;;
  https://proxy.golang.org/mvdan.cc/sh/v3/@v/v3.10.0.info) printf '{"Version":"v3.10.0","Time":"$d10"}' ;;
  https://proxy.golang.org/mvdan.cc/sh/v3/@v/v3.9.0.info) printf '{"Version":"v3.9.0","Time":"$d30"}' ;;
  *) exit 22 ;;
esac
FAKE
chmod +x "$fixture/bin/curl"

# 3.10.0 sorts above 3.9.0 by version, not by string; 3.12.0 is too new and
# 4.0.0-beta.1 a prerelease.
cat > "$fixture/r/npm" <<JSON
{"time":{"created":"$d30","modified":"$d3","3.9.0":"$d30","3.10.0":"$d10","4.0.0-beta.1":"$d10","3.12.0":"$d3"}}
JSON
# 0.8.0 is yanked, 0.9.0rc1 a prerelease, 0.10.0 too new.
cat > "$fixture/r/pypi" <<JSON
{"releases":{"0.7.0":[{"upload_time_iso_8601":"$d30","yanked":false}],"0.8.0":[{"upload_time_iso_8601":"$d10","yanked":true}],"0.9.0rc1":[{"upload_time_iso_8601":"$d10","yanked":false}],"0.10.0":[{"upload_time_iso_8601":"$d3","yanked":false}],"0.6.0":[]}}
JSON

pick() { out=$(PATH="$fixture/bin:$PATH" bash "$script" "$@" 2>/dev/null); rc=$?; }

pick npm prettier
check "npm: the newest release at least 7 days old, by version order" 3.10.0 "$out"
pick pypi ruff
check "pypi: yanked releases and prereleases are passed over" 0.7.0 "$out"
pick go mvdan.cc/sh/v3/cmd/shfmt
check "go: the module's newest old-enough version, read through the proxy" v3.10.0 "$out"
pick npm left-pad
check_rc "a registry that cannot answer is tooling" 2 "$rc"
pick crates ripgrep
check_rc "an unknown registry is a usage error" 2 "$rc"

finish

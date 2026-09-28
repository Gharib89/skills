#!/usr/bin/env bash
# skills/setup-harness/scripts/pick-version.sh: the install check's version
# choice, the newest non-prerelease published at least 7 days ago. The subject
# is the version it prints per registry. A fake `curl` in front of PATH answers
# each registry URL with a fixture whose publish times are relative to now, so
# the 7-day line sits between two releases.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
script=$PWD/skills/setup-harness/scripts/pick-version.sh
iso() { python3 -c "import datetime,sys; print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(days=int(sys.argv[1]))).strftime('%Y-%m-%dT%H:%M:%S.000Z'))" "$1"; }
d30=$(iso 30) d10=$(iso 10) d3=$(iso 3)
# The same instants as an HTTP Last-Modified header, which Maven Central gives.
http() { python3 -c "import datetime,email.utils,sys; print(email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(days=int(sys.argv[1])), usegmt=True))" "$1"; }
h30=$(http 30) h10=$(http 10) h3=$(http 3)

mkdir -p "$fixture/bin" "$fixture/r"
cat > "$fixture/bin/curl" <<FAKE
#!/bin/sh
for a; do url=\$a; done
case \$url in
  https://registry.npmjs.org/prettier) cat "$fixture/r/npm" ;;
  https://pypi.org/pypi/ruff/json) cat "$fixture/r/pypi" ;;
  https://proxy.golang.org/mvdan.cc/sh/v3/@v/list) printf 'v3.8.0\nv3.9.0\nv3.10.0\nv3.11.0-rc1\nv3.11.0\n' ;;
  https://proxy.golang.org/mvdan.cc/sh/v3/@v/v3.8.0.info) printf '{"Version":"v3.8.0"}' ;;
  https://proxy.golang.org/mvdan.cc/sh/v3/@v/v3.11.0.info) printf '{"Version":"v3.11.0","Time":"$d3"}' ;;
  https://proxy.golang.org/mvdan.cc/sh/v3/@v/v3.10.0.info) printf '{"Version":"v3.10.0","Time":"$d10"}' ;;
  https://proxy.golang.org/mvdan.cc/sh/v3/@v/v3.9.0.info) printf '{"Version":"v3.9.0","Time":"$d30"}' ;;
  'https://crates.io/api/v1/crates/cargo-nextest/versions?per_page=100') cat "$fixture/r/crates1" ;;
  'https://crates.io/api/v1/crates/cargo-nextest/versions?per_page=100&seek=X') cat "$fixture/r/crates2" ;;
  https://api.nuget.org/v3/registration5-semver1/csharp-ls/index.json) cat "$fixture/r/nuget" ;;
  https://api.nuget.org/v3/registration5-semver1/csharp-ls/page2.json) cat "$fixture/r/nuget2" ;;
  https://repo1.maven.org/maven2/com/google/googlejavaformat/google-java-format/maven-metadata.xml) cat "$fixture/r/maven" ;;
  https://repo1.maven.org/maven2/com/google/googlejavaformat/google-java-format/1.12/google-java-format-1.12.pom) printf 'HTTP/1.1 200 OK\r\nlast-modified: $h3\r\n\r\n' ;;
  https://repo1.maven.org/maven2/com/google/googlejavaformat/google-java-format/1.10/google-java-format-1.10.pom) printf 'HTTP/1.1 200 OK\r\nlast-modified: $h10\r\n\r\n' ;;
  https://repo1.maven.org/maven2/com/google/googlejavaformat/google-java-format/1.9/google-java-format-1.9.pom) printf 'HTTP/1.1 200 OK\r\nlast-modified: $h30\r\n\r\n' ;;
  'https://hub.docker.com/v2/repositories/hadolint/hadolint/tags?page_size=100') cat "$fixture/r/hub1" ;;
  'https://hub.docker.com/v2/repositories/hadolint/hadolint/tags?page=2&page_size=100') cat "$fixture/r/hub2" ;;
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

# crates.io pages by `meta.next_page`: 0.9.12 is too new, 0.9.11 yanked, and
# the pick sits on page 2 beside a prerelease.
cat > "$fixture/r/crates1" <<JSON
{"versions":[{"num":"0.9.12","created_at":"$d3","yanked":false},{"num":"0.9.11","created_at":"$d10","yanked":true}],"meta":{"next_page":"?per_page=100&seek=X"}}
JSON
cat > "$fixture/r/crates2" <<JSON
{"versions":[{"num":"0.9.10-rc.1","created_at":"$d10","yanked":false},{"num":"0.9.9","created_at":"$d10","yanked":false},{"num":"0.9.8","created_at":"$d30","yanked":false}],"meta":{"next_page":null}}
JSON
# NuGet inlines some registration pages and links others by @id; an unlisted
# release (0.28.0) is NuGet's yank.
cat > "$fixture/r/nuget" <<JSON
{"items":[{"items":[{"catalogEntry":{"version":"0.26.0","published":"$d30","listed":true}}]},{"@id":"https://api.nuget.org/v3/registration5-semver1/csharp-ls/page2.json"}]}
JSON
cat > "$fixture/r/nuget2" <<JSON
{"items":[{"catalogEntry":{"version":"0.27.0","published":"$d10","listed":true}},{"catalogEntry":{"version":"0.28.0","published":"$d10","listed":false}},{"catalogEntry":{"version":"0.29.0-beta.1","published":"$d10","listed":true}},{"catalogEntry":{"version":"0.30.0","published":"$d3","listed":true}}]}
JSON
# Maven Central lists versions in its metadata and dates each by the pom's
# Last-Modified; 1.12 is too new, 1.11-rc1 a prerelease.
cat > "$fixture/r/maven" <<XML
<metadata><versioning><versions>
      <version>1.9</version>
      <version>1.10</version>
      <version>1.11-rc1</version>
      <version>1.12</version>
</versions></versioning></metadata>
XML
# Docker Hub pages by `next`; latest and a -debian variant are not versions.
cat > "$fixture/r/hub1" <<JSON
{"next":"https://hub.docker.com/v2/repositories/hadolint/hadolint/tags?page=2&page_size=100","results":[{"name":"latest","tag_last_pushed":"$d3"},{"name":"v2.16.0","tag_last_pushed":"$d3"},{"name":"v2.15.1-debian","tag_last_pushed":"$d10"}]}
JSON
cat > "$fixture/r/hub2" <<JSON
{"next":null,"results":[{"name":"v2.15.1","tag_last_pushed":"$d10"},{"name":"v2.14.0","tag_last_pushed":"$d30"}]}
JSON

pick() { out=$(PATH="$fixture/bin:$PATH" bash "$script" "$@" 2>/dev/null); rc=$?; }

pick npm prettier
check "npm: the newest release at least 7 days old, by version order" 3.10.0 "$out"
pick pypi ruff
check "pypi: yanked releases and prereleases are passed over" 0.7.0 "$out"
pick go mvdan.cc/sh/v3/cmd/shfmt
check "go: the module's newest old-enough version, read through the proxy, past one with no publish time" v3.10.0 "$out"
pick npm left-pad
check_rc "a registry that cannot answer is tooling" 2 "$rc"
pick crates cargo-nextest
check "crates: yanked releases and prereleases are passed over, across pages" 0.9.9 "$out"
pick nuget csharp-ls
check "nuget: unlisted releases are passed over, linked pages are read" 0.27.0 "$out"
pick maven com.google.googlejavaformat:google-java-format
check "maven: each version dated by its pom's Last-Modified, by version order" 1.10 "$out"
pick dockerhub hadolint/hadolint
check "dockerhub: version tags only, across pages" v2.15.1 "$out"
pick gems rails
check_rc "an unknown registry is a usage error" 2 "$rc"

finish

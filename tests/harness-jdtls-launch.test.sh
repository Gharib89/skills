#!/usr/bin/env bash
# skills/setup-harness/templates/jdtls-launch.sh: the vendored jdtls plugin's
# launcher. The subject is what it runs: a pinned build it fetched and checked,
# or nothing. A fake `curl` in front of PATH serves a stub jdtls tarball at the
# repo.eclipse.org URL and counts its calls, and the cache sits under a
# throwaway XDG_CACHE_HOME.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
script=$PWD/skills/setup-harness/templates/jdtls-launch.sh
v=1.61.0.20260903134612

mkdir -p "$fixture/bin" "$fixture/build/bin" "$fixture/cache"
printf '#!/bin/sh\necho "jdtls $*"\n' > "$fixture/build/bin/jdtls"
chmod +x "$fixture/build/bin/jdtls"
tar czf "$fixture/build.tar.gz" -C "$fixture/build" bin
sha=$( (sha256sum 2>/dev/null || shasum -a 256) < "$fixture/build.tar.gz" | cut -d' ' -f1)
cat > "$fixture/bin/curl" <<FAKE
#!/bin/sh
for a; do url=\$a; done
echo "\$url" >> "$fixture/calls"
case \$url in https://repo.eclipse.org/content/repositories/jdtls-releases/org/eclipse/jdt/ls/org.eclipse.jdt.ls.product/9.9.9/*) exit 22 ;; esac
case \$url in https://repo.eclipse.org/content/repositories/jdtls-releases/org/eclipse/jdt/ls/org.eclipse.jdt.ls.product/*/org.eclipse.jdt.ls.product-*.tar.gz) ;; *) exit 22 ;; esac
[ -z "\${RIVAL:-}" ] || { mkdir -p "$fixture/cache/harness-jdtls/2.0.0/bin"; printf '#!/bin/sh\necho "rival \$*"\n' > "$fixture/cache/harness-jdtls/2.0.0/bin/jdtls"; chmod +x "$fixture/cache/harness-jdtls/2.0.0/bin/jdtls"; }
cat "$fixture/build.tar.gz"
FAKE
chmod +x "$fixture/bin/curl"

launch() { out=$(PATH="$fixture/bin:$PATH" XDG_CACHE_HOME="$fixture/cache" bash "$script" "$@" 2>/dev/null); rc=$?; }
calls() { wc -l < "$fixture/calls" 2>/dev/null | tr -d ' ' || echo 0; }

launch "$v" 0000000000000000000000000000000000000000000000000000000000000000 -data ws
check_rc "a build whose sha256 differs from the pin is refused" 1 "$rc"
check "a refused build is never run" "" "$out"
check "a refused build leaves no cache" "" "$(ls "$fixture/cache/harness-jdtls" 2>/dev/null)"

launch "$v" "$sha" -data ws
check_rc "a build matching the pin runs" 0 "$rc"
check "the pinned build's bin/jdtls gets the launch's arguments" "jdtls -data ws" "$out"
check "a kept build leaves only the cached version behind" "$v" "$(ls "$fixture/cache/harness-jdtls")"

launch "$v" "$sha" -data ws
check "a second launch runs the cached build" "jdtls -data ws" "$out"
check "a second launch downloads nothing" 2 "$(calls)"

launch 9.9.9 "$sha"
check_rc "a download that fails is tooling, not a refusal" 2 "$rc"
check "a failed download leaves no cache" "$v" "$(ls "$fixture/cache/harness-jdtls")"

printf 'not a tarball' > "$fixture/build.tar.gz"
launch 1.0.0 "$( (sha256sum 2>/dev/null || shasum -a 256) < "$fixture/build.tar.gz" | cut -d' ' -f1)"
check_rc "a build that does not unpack is tooling, not a refusal" 2 "$rc"
check "a build that does not unpack leaves no cache" "$v" "$(ls "$fixture/cache/harness-jdtls")"

launch
check_rc "a launch with no pin is a usage error" 2 "$rc"

# A rival first launch of 2.0.0 lands its build while this one downloads.
tar czf "$fixture/build.tar.gz" -C "$fixture/build" bin
check "a build a rival launch cached first is the one run" "rival -data ws" "$(PATH="$fixture/bin:$PATH" XDG_CACHE_HOME="$fixture/cache" RIVAL=1 bash "$script" 2.0.0 "$sha" -data ws 2>/dev/null)"
check "a rival's cached build gets no second copy inside it" "bin" "$(ls "$fixture/cache/harness-jdtls/2.0.0")"

finish

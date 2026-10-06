#!/usr/bin/env bash
# preflight's existing-branch check looks for `*-<n>` on origin. A free-text run
# (`preflight none`) has no issue number, and its branch is `<type>/<slug>-none`:
# a leftover branch of an earlier free-text run is not this run, so `none`
# skips the check, while an issue number still refuses on its own branch.
#
# Origin is a local bare repo holding both branches. The checkout's origin URL
# is a bare path, so a `git` shim answers `remote get-url origin` with the
# GitHub URL host detection needs and hands every other call to the real git.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

scripts=$PWD/skills/ship/scripts
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
real_git=$(command -v git)
g() { "$real_git" -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
export GIT_ALLOW_PROTOCOL=file
mkdir -p "$SHIP_FAKE" "$work/bin"
{
  g init -q --bare "$work/origin.git"
  g clone -q "$work/origin.git" "$work/repo"
  cd "$work/repo"
  g commit -q --allow-empty -m init && g push -q origin main
  g push -q origin main:chore/x-none main:feat/y-5
} >/dev/null 2>&1 || { echo "fixture setup failed" >&2; exit 2; }
cat > "$work/bin/git" <<SHIM
#!/usr/bin/env bash
[ "\$*" = "remote get-url origin" ] && { echo https://github.com/owner/repo.git; exit 0; }
exec "$real_git" "\$@"
SHIM
chmod +x "$work/bin/git"

printf 'me\n'   > "$SHIP_FAKE/host_identity.1.json"
printf 'true\n' > "$SHIP_FAKE/host_can_push.1.json"
preflight() { ( cd "$work/repo" && PATH="$work/bin:$PATH" bash "$scripts/preflight.sh" "$@" 2>/dev/null ); }
branch_reasons() { jq -c '[.reasons[] | select(startswith("existing branch"))]' <<<"$1"; }

check "none ignores a leftover *-none branch" '[]' "$(branch_reasons "$(preflight none)")"
check "an issue number still refuses on its own branch" '["existing branch: feat/y-5"]' \
  "$(branch_reasons "$(preflight 5)")"

finish

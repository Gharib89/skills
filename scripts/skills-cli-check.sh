#!/usr/bin/env bash
# Every machine writes the same skills-lock.json only when every refresh and
# install line runs the same skills CLI, so this repo pins one version, `$pin`
# below. 1.8.1 writes lock version 2, and its v1-to-v2 migration blanks the
# computedHash of every entry whose `.agents/skills/<name>/` folder is missing,
# which every `--agent claude-code` install is; the CLI then reads that entry
# as locally modified. 1.7.x refuses a version 2 lock outright. So this fails
# a lock that is not version 2, an entry with no 64-hex computedHash, and any
# `npx skills` line in the files this repo writes that names no version or
# another one. Changelogs and ADRs record past lines and are not read.
# `scripts/derived-copies-check.sh` runs this, so it reports under
# `scripts/check.sh full`'s `derived-copies` row.
#
#   scripts/skills-cli-check.sh [<root>]
#
# stdout: one line per fault, each naming its fix
# exit: 0 clean · 1 a fault · 2 tooling
set -uo pipefail
pin=skills@1.8.1
root=${1:-.}
cd "$root" || exit 2
[ -f skills-lock.json ] || { echo 'cannot read skills-lock.json' >&2; exit 2; }
version=$(jq -r '.version' skills-lock.json) || { echo 'cannot parse skills-lock.json' >&2; exit 2; }

rc=0
[ "$version" = 2 ] || { echo "skills-lock.json is version $version, not 2: refresh it with npx $pin, then re-add each GitHub entry at its locked ref"; rc=1; }
blank=$(jq -r --arg pin "$pin" '.skills | to_entries[]
  | select(.value.computedHash // "" | test("^[0-9a-f]{64}$") | not)
  | "skills-lock.json: \(.key) has no computedHash; re-add it at its locked ref: npx \($pin) add \(.value.source)\(if .value.ref then "#" + .value.ref else "" end) --skill \(.key) --agent claude-code -y"' skills-lock.json) \
  || { echo 'cannot parse skills-lock.json' >&2; exit 2; }
[ -z "$blank" ] || { printf '%s\n' "$blank"; rc=1; }

# `npx [-y] skills` then a space (no version) or `@<version>`; the word after
# `skills` is the CLI's, so `npx skills-foo` is another package and no hit.
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  loc=${hit%%:npx*} cmd=${hit#"$loc":}
  case $cmd in
    "npx $pin "*|"npx -y $pin "*) ;;
    *@*) v=${cmd#npx }; v=${v#-y }; v=${v%% *}
         echo "$loc: npx $v, not the pinned npx $pin"; rc=1 ;;
    *) echo "$loc: unversioned npx skills, write npx $pin"; rc=1 ;;
  esac
done < <(grep -rnoE 'npx (-y )?skills(@[^ `]+)? ' --exclude=CHANGELOG.md \
           CLAUDE.md .github docs scripts skills 2>/dev/null | grep -v '^docs/adr/')
exit $rc

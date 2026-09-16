#!/usr/bin/env bash
# Every mechanic answers `--help` with its usage line on stdout, exit 0 and
# nothing on stderr, so a run looks a mechanic's flags up by asking the script.
# The usage strings are written out here rather than read from the scripts: a
# case that lifted the string from the file it checks would pass whatever the
# file said. `tests/run.sh`'s host stub covers the other half of the contract,
# that the answer comes before the adapter loads: a `--help` that reached a host
# logs the call and fails this file whatever the cases said.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

dir=skills/ship/scripts
errfile=$(mktemp); trap 'rm -f "$errfile"' EXIT
covered=""

help_case() { # <mechanic> <usage>
  local m=$1 usage=$2 out rc
  covered="$covered$m
"
  out=$(bash "$dir/$m.sh" --help 2>"$errfile"); rc=$?
  check "$m --help prints its usage" "$usage" "$out"
  check_rc "$m --help exits 0" 0 "$rc"
  check "$m --help writes nothing on stderr" "" "$(cat "$errfile")"
}

help_case base-fresh     'usage: base-fresh'
help_case ci-wait        'usage: ci-wait <pr> [--timeout <s>] [--interval <s>]'
help_case cleanup        'usage: cleanup <issue|none>'
help_case comment-pr     'usage: comment-pr <pr> --body-file <path>'
help_case file-issue     'usage: file-issue --title "<title>" --body-file <path> --label <marker> [--distinct-from <n>[,<n>]]'
help_case isolate        'usage: isolate <issue|none> <type> <slug> [--carry <file>...] [--in-place]'
help_case list-prs       'usage: list-prs --open'
help_case manage-issue   'usage: manage-issue <issue> take|release|handback "<reason>"|close'
help_case merge          'usage: merge <pr> <issue|none> [--worktree <path>]'
help_case open-pr        'usage: open-pr <issue|none> --title "<subject>" --body-file <path>'
help_case poll-pr        'usage: poll-pr <pr> [--brief] [--await-review <login>] [--since <iso>] [--full <id>[,<id>]] [--timeout <s>] [--interval <s>]'
help_case preflight      'usage: preflight <issue|none> [--unattended]'
help_case read-issue     'usage: read-issue <issue>'
help_case read-pr        'usage: read-pr <pr>'
help_case reflect        'usage: reflect <issue> <pr>'
help_case reply-thread   'usage: reply-thread <pr> <thread-id> --body-file <path>'
help_case request-review 'usage: request-review <pr> <login> [--comment <phrase>]'
help_case resolve-thread 'usage: resolve-thread <pr> <thread-id>'
help_case select         'usage: select'
help_case tooling        'usage: tooling [--install]'
help_case update-pr-body 'usage: update-pr-body <pr> (--section <name> | --preamble) --body-file <path>'
help_case update-pr-title 'usage: update-pr-title <pr> --title "<subject>"'

# A mechanic added without a case above would leave the contract untested for
# the one mechanic nobody thought about.
present=$(ls "$dir"/*.sh | sed 's|.*/||; s|\.sh$||' | grep -v '^_lib$' | sort)
check "every mechanic has a case" "$present" "$(printf '%s' "$covered" | sort)"

finish

#!/usr/bin/env bash
# skills/ship/scripts/run-file.sh `call`: a direct call is logged under the Run
# file's `## Direct calls` before the run makes it, and only in the host's REST
# form, so a cloud run never meets the proxy's GraphQL refusal (#254, ADR 0010).
# The seam is `run-file call <why> --file <run file> -- <command>...`: an exit
# code, one JSON answer, and the Run file's bytes.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
m=$PWD/skills/ship/scripts/run-file.sh
rf=$(bash "$m" init 9 --scratchpad "$T/sp" | jq -r .run_file)

# call <args>...: sets out, status and err for one call.
call() { out=$(bash "$m" call "$@" 2>/dev/null); status=$?; err=$(jq -r '.error // empty' <<<"$out" 2>/dev/null); }
section() { awk '/^## /{ f = ($0 == "## Direct calls") } f' "$rf"; }

check "init gives direct calls a section of their own" "## Direct calls" "$(grep -x '## Direct calls' "$rf")"

call 'retitle after phase 1 narrowed it' --file "$rf" -- gh api -X PATCH repos/o/r/issues/9 -f 'title=new title'
check_rc "a gh api call is accepted" 0 "$status"
check "the line names the shell-quoted command and why" \
  "- gh api -X PATCH repos/o/r/issues/9 -f title=new\\ title · retitle after phase 1 narrowed it" \
  "$(section | grep '^- gh api')"
check "the answer names the command" "gh api -X PATCH repos/o/r/issues/9 -f title=new\\ title" "$(jq -r .command <<<"$out")"

call 'read a work item' --issue 9 --scratchpad "$T/sp" -- az rest --method get --url https://dev.azure.com/o/_apis/wit/workitems/9
check_rc "an az rest call is accepted" 0 "$status"
check "the az rest line lands below the first" "- az rest --method get --url https://dev.azure.com/o/_apis/wit/workitems/9 · read a work item" "$(section | grep '^- ' | tail -n 1)"

before=$(cat "$rf")
call 'retitle' --file "$rf" -- gh issue edit 9 --title x
check_rc "a gh issue edit call is refused" 1 "$status"
check "the refusal names the REST form" "a direct call goes through the host's REST form, \`gh api\` or \`az rest\`: gh issue edit 9 --title x" "$err"
call 'partial token' --file "$rf" -- gh apix repos/o/r
check_rc "a word that only starts with api is refused" 1 "$status"
check "the partial-token refusal names the REST form" "a direct call goes through the host's REST form, \`gh api\` or \`az rest\`: gh apix repos/o/r" "$err"
call 'bare' --file "$rf" -- gh api
check_rc "gh api with no argument is refused" 1 "$status"
check "the bare refusal names the REST form" "a direct call goes through the host's REST form, \`gh api\` or \`az rest\`: gh api" "$err"
# `gh api graphql` is GraphQL, which the cloud proxy refuses as `gh issue edit`'s calls are.
call 'graphql' --file "$rf" -- gh api graphql -f 'query={viewer{login}}'
check_rc "gh api graphql is refused" 1 "$status"
check "the graphql refusal names the REST form" "a direct call goes through the host's REST form, \`gh api\` or \`az rest\`: gh api graphql -f query=\{viewer\{login\}\}" "$err"
call 'graphql late' --file "$rf" -- gh api -H 'X: y' graphql
check_rc "a graphql endpoint after a flag is refused" 1 "$status"
check "the late graphql refusal names the REST form" "a direct call goes through the host's REST form, \`gh api\` or \`az rest\`: gh api -H X:\ y graphql" "$err"
call 'graphql path' --file "$rf" -- gh api /graphql -f 'query=x'
check_rc "a /graphql path is refused" 1 "$status"
call 'graphql url' --file "$rf" -- gh api https://api.github.com/graphql
check_rc "a graphql URL is refused" 1 "$status"
check "the graphql URL refusal names the REST form" "a direct call goes through the host's REST form, \`gh api\` or \`az rest\`: gh api https://api.github.com/graphql" "$err"
check "a refused call writes nothing" "$before" "$(cat "$rf")"

usage=$(bash "$m" --help | head -n 1)
call --file "$rf" -- gh api repos/o/r
check_rc "no why is a usage error" 2 "$status"
check "no why answers the usage line" "$usage" "$err"
call 'why' --file "$rf" gh api repos/o/r
check_rc "a command without the -- separator is a usage error" 2 "$status"
check "a missing separator answers the usage line" "$usage" "$err"
call $'two\nlines' --file "$rf" -- gh api repos/o/r
check_rc "a why holding a newline is refused" 2 "$status"
check "the newline refusal says why" "a direct call's why is one line" "$err"
check "a refused usage writes nothing" "$before" "$(cat "$rf")"

finish

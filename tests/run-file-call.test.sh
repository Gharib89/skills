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
check "the /graphql refusal names the REST form" "a direct call goes through the host's REST form, \`gh api\` or \`az rest\`: gh api /graphql -f query=x" "$err"
call 'graphql url' --file "$rf" -- gh api https://api.github.com/graphql
check_rc "a graphql URL is refused" 1 "$status"
check "the graphql URL refusal names the REST form" "a direct call goes through the host's REST form, \`gh api\` or \`az rest\`: gh api https://api.github.com/graphql" "$err"
call 'graphql slash' --file "$rf" -- gh api graphql/
check_rc "a graphql endpoint with a trailing slash is refused" 1 "$status"
call 'graphql query' --file "$rf" -- gh api 'https://api.github.com/graphql?x=1'
check_rc "a graphql URL with a query string is refused" 1 "$status"
call 'graphql fragment' --file "$rf" -- gh api 'https://api.github.com/graphql#frag'
check_rc "a graphql URL with a fragment is refused" 1 "$status"
# A credential would reach the Run file and the summary an unattended run posts.
cred_err="a direct call carries no credential: the host CLI authenticates it, so drop the Authorization header"
call 'auth' --file "$rf" -- gh api repos/o/r -H 'Authorization: Bearer s3cr3t'
check_rc "an Authorization header is refused" 1 "$status"
check "the credential refusal leaves the command out" "$cred_err" "$err"
call 'auth' --file "$rf" -- gh api repos/o/r '--header=authorization:token s3cr3t'
check_rc "an attached lower-case header is refused" 1 "$status"
call 'auth' --file "$rf" -- gh api -HAuthorization:s3cr3t repos/o/r
check_rc "an attached short header is refused" 1 "$status"
call 'auth' --file "$rf" -- gh api '-H=Authorization: s3cr3t' repos/o/r
check_rc "a short header with = is refused" 1 "$status"
call 'auth' --file "$rf" -- gh api repos/o/r -H ' authorization : s3cr3t'
check_rc "a header with spaces around its name is refused" 1 "$status"
call 'auth' --file "$rf" -- az rest --url https://dev.azure.com/o/_apis/x --headers '{ "Authorization": "Bearer s3cr3t"}'
check_rc "a spaced JSON Authorization header is refused" 1 "$status"
call 'auth' --file "$rf" -- az rest --url https://dev.azure.com/o/_apis/x --headers '{"Content-Type":"application/json","Authorization":"Bearer s3cr3t"}'
check_rc "a JSON header object with Authorization as a later key is refused" 1 "$status"
call 'auth' --file "$rf" -- gh api -iHAuthorization:s3cr3t repos/o/r
check_rc "a header in a short-flag cluster is refused" 1 "$status"
call 'auth' --file "$rf" -- az rest --url https://dev.azure.com/o/_apis/x --headers 'Authorization=Bearer s3cr3t'
check_rc "an az rest Authorization header is refused" 1 "$status"
call 'auth' --file "$rf" -- az rest --url https://dev.azure.com/o/_apis/x --headers '{"Authorization": "Bearer s3cr3t"}'
check_rc "a JSON Authorization header is refused" 1 "$status"
check "a refused call writes nothing" "$before" "$(cat "$rf")"

call 'comment' --file "$rf" -- gh api repos/o/r/issues/9/comments -f body=see/graphql -f note=graphql -f 'title=Authorization: how'
check_rc "a REST call whose field values name graphql or Authorization is accepted" 0 "$status"
check "the decoy call is logged" "- gh api repos/o/r/issues/9/comments -f body=see/graphql -f note=graphql -f title=Authorization:\\ how · comment" "$(section | grep '^- ' | tail -n 1)"
call 'saml' --file "$rf" -- gh api orgs/o/credential-authorizations
check_rc "an endpoint naming authorizations is accepted" 0 "$status"
call 'body' --file "$rf" -- az rest --method post --url https://dev.azure.com/o/_apis/x --body '{"text":"Authorization: see docs"}'
check_rc "an az rest body naming Authorization is accepted" 0 "$status"
before=$(cat "$rf")

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

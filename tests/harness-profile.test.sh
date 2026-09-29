#!/usr/bin/env bash
# skills/setup-harness/scripts/harness-profile-check.sh: the harness profile's
# Schema 2 grammar. The subject is the verdict a setup-harness run reads after
# writing a profile: exit 0 and silence for a valid one, exit 1 and one line
# per violation otherwise. The template is the first valid profile; each case
# after it breaks one rule in a copy.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
checker=skills/setup-harness/scripts/harness-profile-check.sh
template=skills/setup-harness/templates/harness-profile.md

run() { out=$(bash "$checker" "$1" 2>/dev/null); rc=$?; }
# <case> <sed script>: a copy of the template with the edit applied.
variant() { sed "$2" "$template" > "$fixture/$1.md"; printf '%s' "$fixture/$1.md"; }

run "$template"
check_rc "the template is a valid profile" 0 "$rc"
check "a valid profile prints nothing" "" "$out"

run "$(variant proven 's/^Proof: unproven/Proof: 93bfa43/; s/^Setup: None./Setup: .claude\/hooks\/cloud-setup.sh/; s/^Turn: default/Turn: override 120s: the integration suite needs a database/; s/^Local-only: None./Local-only: language server: operator'"'"'s choice: slow laptop\
Local-only: browser: needs a GPU/; s/^Root: None./Root: api\/pom.xml: Maven has no lockfile\
Root: worker\/go.mod: a library with no go.sum/; s/^Declined: None./Declined: pytest-testmon: we run the full suite/')"
check_rc "overrides, a proof, a setup path and repeated lines are valid" 0 "$rc"

run "$(variant local 's/^Verdict: cloud-first/Verdict: local-only: operator'"'"'s choice: VPN-only database/')"
check_rc "a local-only verdict with its reason is valid" 0 "$rc"

run "$(variant noschema '/^Schema: 2/d')"
check_rc "a profile with no Schema line fails" 1 "$rc"
check "the missing Schema line is named" "missing Schema: line before the first ## heading" "$out"

run "$(variant ahead 's/^Schema: 2/Schema: 3/')"
check "a schema this checker does not read is named" "Schema: 3; this checker reads Schema 2" "$out"

run "$(variant behind 's/^Schema: 2/Schema: 1/')"
check "a Schema 1 profile is refused" "Schema: 1; this checker reads Schema 2" "$out"

run "$(variant noheading '/^## Declined/,$d')"
check "a missing heading is named" "headings out of order or missing: want Claude Code, Check entry point, Budgets, Cloud, Roots, Local-only, Declined" "$out"

run "$(variant noroots '/^## Roots/,/^Root:/d')"
check "a missing ## Roots is named" "headings out of order or missing: want Claude Code, Check entry point, Budgets, Cloud, Roots, Local-only, Declined" "$out"

run "$(variant order 's/^## Budgets/## Tmp/; s/^## Check entry point/## Budgets/; s/^## Tmp/## Check entry point/')"
check_rc "headings out of order fail" 1 "$rc"

run "$(variant nolocation '/^Location:/d')"
check "a missing label is named with its heading" "## Check entry point: missing Location:" "$out"

run "$(variant budget 's/^Edit: default/Edit: 10/')"
check "a budget that is neither default nor an override is named" \
  "## Budgets: Edit: want default or override <N>s: <reason>, got 10" "$out"

run "$(variant noreason 's/^Edit: default/Edit: override 10s/')"
check_rc "an override with no reason fails" 1 "$rc"

run "$(variant verdict 's/^Verdict: cloud-first/Verdict: local-only/')"
check "a local-only verdict with no reason is named" \
  "## Cloud: Verdict: want cloud-first or local-only: <reason>, got local-only" "$out"

run "$(variant proof 's/^Proof: unproven/Proof: yes/')"
check "a proof that is neither a sha nor unproven is named" \
  "## Cloud: Proof: want <sha> or unproven, got yes" "$out"

run "$(variant declined 's/^Declined: None./Declined: prek/')"
check "a declined line with no reason is named" \
  "## Declined: Declined: want <proposal>: <reason> or None., got prek" "$out"

run "$(variant rootreason 's/^Root: None./Root: api\/pom.xml/')"
check "a root line with no reason is named" \
  "## Roots: Root: want <manifest>: <reason> or None., got api/pom.xml" "$out"

run "$(variant floor 's/^Floor: 2.1.277/Floor: latest/')"
check "a floor that is not a version is named" "## Claude Code: Floor: want <major>.<minor>.<patch>, got latest" "$out"

run "$fixture/absent.md"
check_rc "an unreadable profile is tooling" 2 "$rc"

finish

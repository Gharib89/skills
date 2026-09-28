#!/usr/bin/env bash
# skills/setup-skills/local-gate-harness.sh: the thin local gate setup-skills
# writes over a harness. The subject is how it reads `check.sh full`: each check
# becomes a gate of the same name, `skipped` as `pass`, and an answer outside the
# contract (exit 2, exit 3, output that is not the JSON line) as one `check:
# unavailable` gate with check.sh's stderr forwarded. check.sh is a stub that
# prints what the case sets and logs how it was called.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
d=$fixture/repo; mkdir -p "$d/scripts"
sed 's|__DEPS__|true|; s|__RUNNER__|scripts/node.sh|; s|__CHECK__|scripts/check.sh|' \
  skills/setup-skills/local-gate-harness.sh > "$d/scripts/local-gate.sh"
# The stub check.sh: prints $STUB_OUT, $STUB_ERR on stderr, exits $STUB_RC, and
# logs its arguments and whether CHECK_DEADLINE reached it.
cat > "$d/scripts/check.sh" <<'STUB'
#!/usr/bin/env bash
echo "$* deadline=${CHECK_DEADLINE-unset}" >> "$CALLS"
printf '%s' "$STUB_ERR" >&2
printf '%s' "$STUB_OUT"
exit "$STUB_RC"
STUB
printf '#!/usr/bin/env bash\necho "node $*" >> "$CALLS"\n' > "$d/scripts/node.sh"
# gitleaks: a pass, so `secrets` does not depend on the machine running the test.
mkdir -p "$fixture/bin"; printf '#!/bin/sh\nexit 0\n' > "$fixture/bin/gitleaks"
chmod +x "$d/scripts/check.sh" "$d/scripts/node.sh" "$fixture/bin/gitleaks"
git -C "$d" init -q && git -C "$d" add -A \
  && git -C "$d" -c user.email=t@t -c user.name=t commit -qm base && git -C "$d" tag base

# gate <stdout> <rc> <stderr> [flags...]: run the gate; sets out, rc, err, calls.
gate() {
  : > "$fixture/calls"
  out=$(cd "$d" && PATH="$fixture/bin:$PATH" CALLS="$fixture/calls" STUB_OUT=$1 STUB_RC=$2 STUB_ERR=$3 CHECK_DEADLINE=99 \
    bash scripts/local-gate.sh --base base "${@:4}" 2>"$fixture/err"); rc=$?
  err=$(cat "$fixture/err"); calls=$(cat "$fixture/calls")
}
gates() { jq -cS '.gates | del(.secrets)' <<<"$out"; }

gate '{"rung":"full","verdict":"pass","checks":{"lint":"pass","e2e":"skipped"}}' 0 ''
check_rc "check.sh passing: exit 0" 0 "$rc"
check "check.sh passing: each check is a gate, skipped as pass" '{"deps":"pass","e2e":"pass","lint":"pass"}' "$(gates)"
check "check.sh runs once, as full, with no CHECK_DEADLINE" "full deadline=unset" "$calls"

gate '{"rung":"full","verdict":"fail","checks":{"lint":"pass","tests":"fail"}}' 1 'tests: 1 failed'
check_rc "a failing check: exit 1" 1 "$rc"
check "a failing check: verdict fail, the check its own gate" 'fail {"deps":"pass","lint":"pass","tests":"fail"}' \
  "$(jq -r .verdict <<<"$out") $(gates)"
check "a failing check: check.sh's stderr is forwarded" "tests: 1 failed" "$err"

for c in "2|tooling: uv missing|exit 2" "3|over budget|exit 3" "0|not json|a line outside the contract"; do
  IFS='|' read -r code msg name <<<"$c"
  stdout='{"rung":"full","verdict":"unavailable","checks":{"lint":"unavailable"}}'
  [ "$name" = "exit 2" ] || [ "$name" = "exit 3" ] || stdout=$msg
  gate "$stdout" "$code" "$msg"
  check_rc "$name: exit 2" 2 "$rc"
  check "$name: one check gate, unavailable" '{"check":"unavailable","deps":"pass"}' "$(gates)"
done
check "exit 3: check.sh's stderr is forwarded" "over budget" "$(gate '' 3 'over budget'; printf '%s' "$err")"
check "exit 0, a line outside the contract: check.sh's stderr is forwarded" "noise" "$(gate 'not json' 0 'noise'; printf '%s' "$err")"
long=$(seq 1 50)
check "exit 2: check.sh's stderr is capped at its last 40 lines" "$(seq 11 50)" "$(gate '' 2 "$long"; printf '%s' "$err")"
check "a failing check: check.sh's stderr is capped at its last 40 lines" "$(seq 11 50)" \
  "$(gate '{"checks":{"tests":"fail"}}' 1 "$long"; printf '%s' "$err")"

gate '{"checks":{"lint":"pass"}}
{"checks":{"lint":"pass"}}' 0 ''
check_rc "two JSON lines: exit 2" 2 "$rc"
check "two JSON lines: still one verdict object, check unavailable" '{"check":"unavailable","deps":"pass"}' "$(gates)"

gate '{"rung":"full","verdict":"fail","checks":{"secrets":"fail","deps":"fail"}}' 1 ''
check_rc "a check named like a Ship gate: its failure is not masked" 1 "$rc"
check "a check named like a Ship gate: the worse of the two stands" '{"deps":"fail","secrets":"fail"}' \
  "$(jq -cS '.gates' <<<"$out")"

gate '{"rung":"full","verdict":"pass","checks":{"lint":"over-budget"}}' 0 ''
check "a status outside the contract reads as unavailable" '{"deps":"pass","lint":"unavailable"}' "$(gates)"

gate '' 0 '' --small tests/test_one.py
check "--small: the node runs directly and check.sh does not" "node tests/test_one.py" "$calls"
check "--small: secrets, deps and the node are the gates" '{"deps":"pass","tests":"pass"}' "$(gates)"
check "--small: lane small" "small" "$(jq -r .lane <<<"$out")"

finish

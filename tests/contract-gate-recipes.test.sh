#!/usr/bin/env bash
# scripts/contract-check.sh check 14, widened (#1181): a recipe in a skill's
# Markdown that omits a required flag or a <json> value form fails the gate,
# whether it is written as a bare name, `<name>.sh` or a path to the script, over
# a line break, as a verb of a mechanic with alternatives or in a shell fence.
# Split from tests/contract-gate-usage.test.sh; the shared fixtures are in
# tests/contract-gate-lib.sh.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/contract-gate-lib.sh

# 14, widened (#1181): the gaps four super-agent PRs shipped a recipe through.
# Real super-agent mechanics, since `ledger` has the alternatives and the `<json>`
# slot. One bad doc with a line per gap, and its corrected twin alone.
sa=$fixture/sa; rm -rf "$sa"; cp -r skills/super-agent "$sa"
cat > "$sa/zz.md" <<'EOT'
By name: `quota.sh --save f --wake w` and `scripts/quota.sh --save f --wake w`.
By verb: `ledger.sh --ledger l wait k --after j`.
Over a line: `ledger.sh --ledger l wait k
--after j`.
By value: `ledger.sh --ledger l set k branch main`.
By lead flag: `ledger.sh get k`.

```sh
scripts/quota.sh --save f --wake w
FOO=1 scripts/ledger.sh --ledger l wait k \
  --after j | jq .
```

Samples are not read: a text fence, a fence marked, a span marked, a bare name.

```text
scripts/quota.sh --save f --wake w
```

<!-- contract-check: sample -->
```sh
scripts/quota.sh --save f --wake w
```

`quota.sh --save f --wake w` <!-- contract-check: sample -->

~~~bash
$ quota.sh --save f --wake w; echo ok
scripts/quota.sh --save f --wake w && true
~~~

```console
quota.sh --fleet=f --save f --wake w > out
quota.sh --save f --wake w 2>&1
```

Naming the tool is no call: `quota.sh`, `ledger.sh wait`, `run-file gate clean`, `quota.sh --help`.
EOT
run "$sa/scripts" "$sa"
check_rc "a recipe that omits a required flag or value form fails, fenced or not" 1 "$rc"
check "and each gap is named at its line: name form, verb, line break, value, lead flag, fence"   "$sa/zz.md:1: \`quota.sh --save f --wake w\` lacks --fleet from quota's usage line
$sa/zz.md:1: \`scripts/quota.sh --save f --wake w\` lacks --fleet from quota's usage line
$sa/zz.md:2: \`ledger.sh --ledger l wait k --after j\` lacks --reason from ledger's usage line
$sa/zz.md:3: \`ledger.sh --ledger l wait k --after j\` lacks --reason from ledger's usage line
$sa/zz.md:5: \`ledger.sh --ledger l set k branch main\` gives main where ledger's usage line takes a <json> value; quote a string as '\"text\"'
$sa/zz.md:6: \`ledger.sh get k\` lacks --ledger from ledger's usage line
$sa/zz.md:9: \`scripts/quota.sh --save f --wake w\` lacks --fleet from quota's usage line
$sa/zz.md:10: \`scripts/ledger.sh --ledger l wait k --after j\` lacks --reason from ledger's usage line
$sa/zz.md:28: \`quota.sh --save f --wake w\` lacks --fleet from quota's usage line
$sa/zz.md:29: \`scripts/quota.sh --save f --wake w\` lacks --fleet from quota's usage line
$sa/zz.md:34: \`quota.sh --save f --wake w\` lacks --fleet from quota's usage line" "$out"

cat > "$sa/zz.md" <<'EOT'
By name: `quota.sh --fleet f --save f --wake w` and `scripts/quota.sh --fleet f --save f --wake w`.
By verb: `ledger.sh --ledger l wait k --reason r --after j`.
Over a line: `ledger.sh --ledger l wait k
--reason r --after j`.
By value: `ledger.sh --ledger l set k branch '"main"'` and `ledger.sh --ledger l set k stalls 0`.
By lead flag: `ledger.sh --ledger l get k`.

```sh
scripts/quota.sh --fleet f --save f --wake w
FOO=1 scripts/ledger.sh --ledger l wait k --reason r \
  --after j | jq .
```

~~~bash
$ quota.sh --fleet f --save f --wake w; echo ok
scripts/quota.sh --fleet f --save f --wake w && true
~~~

```console
quota.sh --fleet=f --save f --wake w > out
```

```sh
shellcheck scripts/quota.sh scripts/route.sh
git diff -- scripts/quota.sh README.md
```

By value: `ledger.sh --ledger l set k branch "\"main\""` and `ledger.sh --ledger l set k x [1]`.
EOT
run "$sa/scripts" "$sa"
check_rc "the corrected recipes pass" 0 "$rc"
check "and print nothing" "" "$out"

finish

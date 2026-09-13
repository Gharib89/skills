#!/usr/bin/env bash
# ship_id_list: the comma list `poll-pr --full` takes. A pure transformation
# over strings; no call in this file reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

ids()    { ship_id_list "$1" 2>/dev/null; }
verdict() { ship_id_list "$1" >/dev/null 2>&1 && echo accepted || echo rejected; }

check "one id"                '["7"]'       "$(ids '7')"
check "a comma list"          '["7","8"]'   "$(ids '7,8')"
check "spaces around each id" '["7","8"]'   "$(ids ' 7 , 8 ')"
check "an empty element"      '["7","8"]'   "$(ids '7,,8')"
check "a non-numeric host id" '["PRRT_a1"]' "$(ids 'PRRT_a1')"

# Without this, `--full --timeout` reads the next flag as an id and starts a
# poll that matches no row, saying nothing about the mistake.
check "an option-like value is rejected"      rejected "$(verdict '--timeout')"
check "an option among real ids is rejected"  rejected "$(verdict '7,--timeout')"
check "nothing but separators is rejected"    rejected "$(verdict ',,')"
check "an option-like value prints nothing"   ''       "$(ids '--timeout')"

finish

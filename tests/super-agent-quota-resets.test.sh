#!/usr/bin/env bash
# super-agent's `quota` gives each bucket `resets_at`, its reset as an epoch second
# or null, read from each provider's own reset text, the clock pinned by `SA_NOW`.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh
source tests/super-agent-quota-lib.sh

reset
# resets_at: the reset as an epoch, the clock pinned to the fixture's day (2026-11-06)
out=$(SA_NOW=1794000000 Q)
check "claude: resets_at reads the printed time in its zone" "$(TZ=Africa/Cairo date -d 'Nov 11 2026 12pm' +%s)" \
  "$(jq -r '.providers.claude.buckets[] | select(.id == "week") | .resets_at' <<<"$out")"
check "codex: resets_at is the epoch it printed" 1794383419 \
  "$(jq -r '.providers.codex.buckets[] | select(.id == "week") | .resets_at' <<<"$out")"
check "agy: resets_at reads the ISO time" "$(date -u -d 2026-11-13T10:38:55Z +%s)" \
  "$(jq -r '.providers.agy.buckets[] | select(.id == "3p-weekly") | .resets_at' <<<"$out")"
out=$(SA_NOW="$(date -u -d 2026-12-30T12:00:00Z +%s)" Q)
check "claude: a printed day with no year past the read's turns into next year's" "$(TZ=Africa/Cairo date -d 'Nov 11 2027 12pm' +%s)" \
  "$(jq -r '.providers.claude.buckets[] | select(.id == "week") | .resets_at' <<<"$out")"
out=$(SA_NOW="$(date -u -d 2028-11-06T12:00:00Z +%s)" Q)
check "claude: a printed day with no year takes the pinned clock's year, not the real one" \
  "$(TZ=Africa/Cairo date -d 'Nov 11 2028 12pm' +%s)" \
  "$(jq -r '.providers.claude.buckets[] | select(.id == "week") | .resets_at' <<<"$out")"
sa_provider claude 0 "$(jq -cn '{result: "Current session: 1% used · resets 4:40pm (Africa/Cairo)\nCurrent week (all models): 9% used · resets x"}')"
check "claude: a time with no day has resets_at null" null \
  "$(SA_NOW=1794000000 Q | jq -r '.providers.claude.buckets[] | select(.id == "session") | .resets_at')"
sa_provider claude 0 "$(jq -cn '{result: "Current session: 1% used · resets x\nCurrent week (all models): 9% used · resets Nov 11, 12pm (../zoneinfo/UTC)"}')"
check "claude: a zone that climbs out of zoneinfo has resets_at null" null \
  "$(SA_NOW=1794000000 Q | jq -r '.providers.claude.buckets[] | select(.id == "week") | .resets_at')"
sa_provider claude 0 "$(jq -cn '{result: "Current session: 1% used · resets x\nCurrent week (all models): 9% used · resets Nov 11, 12pm (Mars/Base)"}')"
out=$(SA_NOW=1794000000 Q)
check "claude: a reset in an unknown zone, or not a time, has resets_at null" "null null" \
  "$(jq -r '[.providers.claude.buckets[].resets_at] | map(tostring) | join(" ")' <<<"$out")"

finish

#!/usr/bin/env bash
# Fixtures shared by the super-agent route tests; needs $tmp from the sourcing test.
# shellcheck disable=SC2154
# inst <id> <driver> <weekly|null> <auth> [extra json]: one provider entry of a `quota` answer
inst() {
  jq -cn --arg id "$1" --arg d "$2" --argjson w "$3" --arg a "$4" --argjson x "${5:-{\}}" '{($id): ({driver: $d, status: (if $w == null then "unknown" else "available" end),
    reason: null, auth: $a, auth_reason: (if $a == "failed" then "auth command exited 1" else null end),
    buckets: (if $w == null then [] else [{id: "week", window: "weekly", remaining: $w, resets: "x"}] end)} + $x)}'
}
quotas() { jq -cn --argjson p "$(jq -cs 'add' <<<"$*")" '{providers: $p}' > "$tmp/q.json"; }

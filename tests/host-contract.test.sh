#!/usr/bin/env bash
# The host seam's contract, held on both sides of the Host fake: the three
# adapters define one function set, and each default under tests/host-fake/
# defaults/ carries exactly the key set the `_lib.sh` contract comment documents
# for that function, even where the contract also admits `null` (as
# `host_pr_reviewer_blocked`'s does): the default exercises the object shape, and
# a test wanting the null answer writes that fixture itself. A default's `status`
# is held to the vocabulary its entry lists, where the entry lists one. A function added to one real adapter and not the other, or
# a default drifting from the comment, is a mechanic test passing against a host
# that does not exist.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

lib=skills/ship/scripts/_lib.sh
defaults=tests/host-fake/defaults

# <adapter>: the host_* functions it defines, one per line, sorted. The
# adapters read these at source time, and the fake wants SHIP_FAKE to name a
# directory; nothing is called, so nothing is written there.
fns() {
  ( export SHIP_OWNER=o SHIP_REPO=r SHIP_REPO_SLUG=o/r SHIP_ORG=o SHIP_PROJECT=p SHIP_ORG_URL=https://dev.azure.com/o \
      SHIP_FAKE=${TMPDIR:-/tmp}
    # shellcheck source=/dev/null
    source "$lib" && source "$1" && declare -F | awk '$3 ~ /^host_/ {print $3}' | sort )
}
gh_fns=$(fns skills/ship/scripts/host/github.sh)
check "the GitHub adapter defines host functions at all" true "$([ -n "$gh_fns" ] && echo true)"
check "the Azure DevOps adapter defines the GitHub adapter's host functions" "$gh_fns" \
  "$(fns skills/ship/scripts/host/ado.sh)"
check "the Host fake defines the GitHub adapter's host functions" "$gh_fns" "$(fns tests/host-fake.sh)"

# `<fn> <key,key,...>` for every function whose contract line documents an
# object answer, `{...}` or `[{...}]`, keys sorted. The answer is the text after
# `->`, on the function's own line or the next, joined with continuation lines
# while its braces stay open; a key is a top-level name, cut at `:` or `[`.
shapes() {
  sed '/^[^#]/q' "$lib" | awk '
    function flush(   t, i, c, bd, kd, tok, out, n, k, keys) {
      if (fn == "") return
      t = txt; sub(/^[ \t]*/, "", t)
      if (t !~ /^\[?\{/) { fn = ""; return }
      bd = 0; kd = 0; tok = ""; n = 0
      for (i = 1; i <= length(t); i++) {
        c = substr(t, i, 1)
        if (c == "{") { bd++; if (bd == 1) { kd = 0; continue } }
        if (c == "}") { bd--; if (bd == 0) { keys[++n] = tok; break } }
        if (bd < 1) continue
        if (c == "[") kd++
        if (c == "]") kd--
        if (bd == 1 && kd == 0 && c == ",") { keys[++n] = tok; tok = ""; continue }
        tok = tok c
      }
      out = ""
      for (k = 1; k <= n; k++) { sub(/[:\[].*/, "", keys[k]); gsub(/ /, "", keys[k]); out = out keys[k] "\n" }
      printf "%s ", fn
      cmd = "sort | paste -sd, -"; printf "%s", out | cmd; close(cmd)
      fn = ""
    }
    function open(s,   o, cl) { o = gsub(/\{/, "{", s); cl = gsub(/\}/, "}", s); return o > cl }
    /^#   host_/ {
      flush(); fn = $2; arrow = index($0, "->")
      txt = arrow ? substr($0, arrow + 2) : ""; want = !arrow; next
    }
    fn != "" {
      s = $0; sub(/^#[ \t]*/, "", s)
      if (want) { if (s ~ /^->/) { txt = substr(s, 3); want = 0 } else fn = ""; next }
      if (open(txt)) txt = txt s
    }
    END { flush() }'
}
contract=$(shapes)
check "the contract comment documents object answers at all" true "$([ -n "$contract" ] && echo true)"
# The parser reads an entry only at the comment's own indent, so an entry that
# drifted from it would drop out of $contract with nothing to say so: every
# adapter function has to be an entry the parser can see.
check "every adapter function is a contract entry at the parsed indent" "$gh_fns" \
  "$(sed '/^[^#]/q' "$lib" | awk '/^#   host_/ {print $2}' | sort)"

while read -r fn keys; do
  f=$defaults/$fn.json
  if [ ! -f "$f" ]; then check "$fn has a default answer" "$f" "missing"; continue; fi
  check "$fn's default carries the documented key set" "$keys" \
    "$(jq -r 'if type == "array" then .[0] else . end | keys_unsorted | sort | join(",")' "$f")"
done <<<"$contract"

# REVIEW is the one named row shape, documented on a line of its own under
# host_pr_reviews, so the default's rows are held to it separately.
check "host_pr_reviews' default rows carry the documented REVIEW keys" \
  "$(sed -n 's/.*REVIEW = {\([^}]*\)}.*/\1/p' "$lib" | tr , '\n' | sort | paste -sd, -)" \
  "$(jq -r '[.on_head[0], .all[0]] | map(keys_unsorted | sort | join(",")) | unique | join(" ")' "$defaults/host_pr_reviews.json")"

# `<fn> <word|word|...>` for every entry whose continuation lines carry a
# `status: a | b | c.` vocabulary, so a default's status is a word a real adapter
# emits: a fake-driven test passing on any other word passes on a check state
# `ci-wait` and `poll-pr` never see.
vocab=$(sed '/^[^#]/q' "$lib" | awk '
  /^#   host_/ { fn = $2; next }
  fn != "" && /^#[ \t]+status: [a-z_]+( \| [a-z_]+)+\.?$/ {
    s = $0; sub(/^#[ \t]+status: /, "", s); sub(/\.$/, "", s); gsub(/ /, "", s)
    print fn, s
  }')
check "the contract comment documents host_pr_checks' status vocabulary" true \
  "$(awk '$1 == "host_pr_checks" {print "true"}' <<<"$vocab")"
while read -r fn words; do
  check "$fn's default statuses are words its contract entry lists" "" \
    "$(jq -r --arg w "$words" '($w | split("|")) as $v
      | (if type == "array" then .[] else . end) | .status | select(IN($v[]) | not)' \
      "$defaults/$fn.json")"
done <<<"$vocab"

# A default for a function the contract gives no object answer is a shape
# nobody documented.
for f in "$defaults"/*.json; do
  fn=$(basename "$f" .json)
  check "$fn's default answers a documented object shape" "$fn" \
    "$(awk -v f="$fn" '$1 == f {print $1}' <<<"$contract")"
done

finish

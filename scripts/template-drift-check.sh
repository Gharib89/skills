#!/usr/bin/env bash
# Template-drift check: each repo copy of a template setup-skills ships matches
# that template outside its repo-owned regions.
#
# A template is copied into a repo once and owned there. When the template
# changes (a fixed helper, a reworded prompt line) the copy keeps the old text
# until someone diffs the two, which nothing did: the gate script lacked the
# template's `worse` helper and the review workflow carried a fallback-only
# phrase the template had dropped. This is that diff, hard-coded to the three
# pairs, each with the reason for what it exempts.
#
#   scripts/template-drift-check.sh [<root>]      <root> defaults to the repo root
#
# The pairs:
#   skills/setup-skills/local-gate-harness.sh -> scripts/local-gate.sh
#     Exempt in both: the header comment block (the repo describes its own
#     gates there) and the region from `# --- gates` to `# --- end gates`
#     inclusive (the marked slot holding the repo's gates, where the
#     __CHECK__, __DEPS__ and __RUNNER__ placeholders sit).
#   skills/setup-skills/cloud-ship-bootstrap.sh -> scripts/cloud-ship-bootstrap.sh
#     No exemption. __SCANNER__ and __SCANNER_INSTALL__ are filled in the
#     template with the values the copy's own `SCANNER=` and `SCANNER_INSTALL=`
#     lines hold, since the fill is the repo's choice.
#   the on-request workflow in skills/setup-skills/reviewers/github-claude-review.md
#     (the first yaml block under `### .github/workflows/claude-review.yml` after
#     `## The on-request shape`) -> .github/workflows/claude-review.yml
#     __PHRASE__, __INSTRUCTIONS__ and __PRIMARY__ are filled from the `### claude`
#     block of docs/agents/ship.md (Request:, Instructions:, Fallback-for:).
#     Exempt: YAML comment lines in both, since the workflow's comments narrate
#     this repo's history, and in the copy a region between a line
#     `# >>> repo-owned` and a line `# <<< repo-owned`, a deliberate departure
#     the repo marks.
#
# Both sides are compared as whitespace-separated token streams, so a reflowed
# prompt is not drift.
#
# stdout: per drifting pair, `template-drift: <copy> differs from <template>
#         outside its repo-owned regions; make the copy match the template, or
#         change the template (only the review workflow takes a '# >>>
#         repo-owned' region):` and up to 5 indented diff lines,
#         `  template: <token>` and `  copy: <token>`; nothing when clean
# stderr: on tooling, the reason
# exit: 0 every pair matches · 1 a pair drifts · 2 tooling (a file missing or
#       unreadable, a region left open, no profile or workflow block to read)
set -uo pipefail

root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
cd "$root" || { echo "template-drift: cannot enter $root" >&2; exit 2; }

gate_t=skills/setup-skills/local-gate-harness.sh gate_c=scripts/local-gate.sh
boot_t=skills/setup-skills/cloud-ship-bootstrap.sh boot_c=scripts/cloud-ship-bootstrap.sh
wf_t=skills/setup-skills/reviewers/github-claude-review.md wf_c=.github/workflows/claude-review.yml
profile=docs/agents/ship.md

die() { echo "template-drift: $*" >&2; exit 2; }
need() { local f; for f in "$@"; do [ -r "$f" ] || die "cannot read $f"; done; }
need "$gate_t" "$gate_c" "$boot_t" "$boot_c" "$wf_t" "$wf_c" "$profile"

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
found=0

# Reads stdin, drops the header comment block (lines after the shebang up to the
# first one that is not a comment) and the marked gates slot.
strip_gate_regions() {
  awk '
    NR == 1 { print; head = 1; next }
    head && /^#/ { next }
    { head = 0 }
    /^# --- gates -/ { skip = 1 }
    skip { if (/^# --- end gates -/) skip = 0; next }
    { print }
  '
}

# <pairs: placeholder TAB value ...> on argv, stdin to stdout: a literal
# replacement, since a value such as `apt_install gitleaks` or `@claude` would
# need escaping in sed.
fill() {
  awk -v pairs="$(printf '%s\n' "$@")" '
    BEGIN { n = split(pairs, p, "\n") }
    {
      for (i = 1; i <= n; i++) {
        split(p[i], kv, "\t")
        while ((j = index($0, kv[1])) > 0) $0 = substr($0, 1, j - 1) kv[2] substr($0, j + length(kv[1]))
      }
      print
    }
  '
}

# Reads stdin, drops YAML comment lines (first non-blank character `#`) and, in
# the copy, the repo-owned region. A region left open exits 3 rather than
# swallowing the rest of the file.
strip_yaml() {
  awk '
    /^[ \t]*# >>> repo-owned/ { owned = 1; next }
    /^[ \t]*# <<< repo-owned/ { owned = 0; next }
    owned || /^[ \t]*#/ { next }
    { print }
    END { exit owned ? 3 : 0 }
  '
}

# Reads stdin, prints its whitespace-separated tokens one per line.
tokens() { tr -s '[:space:]' '\n' | grep -v '^$'; }

# <copy> <template> <template-tokens> <copy-tokens>: reports one drifting pair.
compare() {
  local out
  if ! diff "$3" "$4" >"$tmp/diff"; then
    out=$(grep '^[<>]' "$tmp/diff" | head -n 5 | sed 's/^< /  template: /; s/^> /  copy: /')
    printf "template-drift: %s differs from %s outside its repo-owned regions; make the copy match the template, or change the template (only the review workflow takes a '# >>> repo-owned' region):\n%s\n" "$1" "$2" "$out"
    found=1
  fi
}

# Pair 1.
strip_gate_regions < "$gate_t" | tokens > "$tmp/t1"
strip_gate_regions < "$gate_c" | tokens > "$tmp/c1"
compare "$gate_c" "$gate_t" "$tmp/t1" "$tmp/c1"

# Pair 2: the fill is read from the copy's own lines.
scanner=$(sed -n 's/^SCANNER=\(.*\)$/\1/p' "$boot_c" | head -n 1)
install=$(sed -n "s/^SCANNER_INSTALL='\(.*\)'\$/\1/p" "$boot_c" | head -n 1)
if [ -z "$scanner" ] || [ -z "$install" ]; then die "$boot_c carries no SCANNER= or SCANNER_INSTALL= line to read the fill from"; fi
fill "$(printf '__SCANNER_INSTALL__\t%s' "$install")" "$(printf '__SCANNER__\t%s' "$scanner")" < "$boot_t" | tokens > "$tmp/t2"
tokens < "$boot_c" > "$tmp/c2"
compare "$boot_c" "$boot_t" "$tmp/t2" "$tmp/c2"

# Pair 3: the template's block, then the profile's fills.
awk '
  /^## The on-request shape/ { shape = 1; next }
  shape && /^### `\.github\/workflows\/claude-review\.yml`/ { heading = 1; next }
  heading && !open && /^```yaml/ { open = 1; next }
  open && /^```/ { exit }
  open { print }
' "$wf_t" > "$tmp/block"
[ -s "$tmp/block" ] || die "$wf_t has no on-request workflow block to compare"

# A profile line `Label: value` in the `### claude` block.
profile_value() {
  awk -v label="$1" '
    /^### / { inblock = ($0 == "### claude"); next }
    inblock && index($0, label ": ") == 1 { print substr($0, length(label) + 3); exit }
  ' "$profile"
}
instructions=$(profile_value Instructions)
request=$(profile_value Request)
primary=$(profile_value Fallback-for)
phrase=${request#comment }
if [ -z "$instructions" ] || [ "$phrase" = "$request" ] || [ -z "$primary" ]; then
  die "$profile's \`### claude\` block lacks an Instructions:, a \`Request: comment <phrase>\` or a Fallback-for: line"
fi

fill "$(printf '__INSTRUCTIONS__\t%s' "$instructions")" "$(printf '__PHRASE__\t%s' "$phrase")" "$(printf '__PRIMARY__\t%s' "$primary")" \
  < "$tmp/block" | strip_yaml | tokens > "$tmp/t3" || die "$wf_t's workflow block has an unclosed repo-owned marker"
strip_yaml < "$wf_c" | tokens > "$tmp/c3" || die "$wf_c has a '# >>> repo-owned' line with no '# <<< repo-owned' after it"
compare "$wf_c" "$wf_t" "$tmp/t3" "$tmp/c3"

exit "$found"

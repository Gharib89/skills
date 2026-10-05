#!/usr/bin/env bash
# scripts/template-drift-check.sh: each repo copy of a shipped template matches
# its template outside the regions the repo owns. Each pair gets a passing
# fixture per exemption (a reflow, a placeholder fill, a comment, a marked
# region) and a failing one carrying exactly one drifting token, run against a
# throwaway root that mirrors the real relative paths; the last case runs the
# check on this repo, where it is the live drift gate.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
script=$PWD/scripts/template-drift-check.sh

gate_t=skills/setup-skills/local-gate-harness.sh
gate_c=scripts/local-gate.sh
boot_t=skills/setup-skills/cloud-ship-bootstrap.sh
boot_c=scripts/cloud-ship-bootstrap.sh
wf_t=skills/setup-skills/reviewers/github-claude-review.md
wf_c=.github/workflows/claude-review.yml

# <name>: a root where every copy matches its template; prints its path.
root() {
  local d="$fixture/$1"
  mkdir -p "$d/skills/setup-skills/reviewers" "$d/scripts" "$d/.github/workflows" "$d/docs/agents"
  cat > "$d/$gate_t" <<'T'
#!/usr/bin/env bash
# template header
# second line
set -uo pipefail
put() { echo old; }
# --- gates ----------
run deps __DEPS__
# --- end gates ------
reduce all
T
  cat > "$d/$gate_c" <<'T'
#!/usr/bin/env bash
# the repo's own header, longer
# than the template's
# by a line
set -uo pipefail
put() { echo old; }
# --- gates ----------
run secrets gitleaks
run version-lines scripts/version-line-check.sh
# --- end gates ------
reduce all
T
  cat > "$d/$boot_t" <<'T'
#!/usr/bin/env bash
SCANNER=__SCANNER__
SCANNER_INSTALL='__SCANNER_INSTALL__'
install "$SCANNER"
T
  cat > "$d/$boot_c" <<'T'
#!/usr/bin/env bash
SCANNER=gitleaks
SCANNER_INSTALL='apt_install gitleaks'
install "$SCANNER"
T
  cat > "$d/$wf_t" <<'T'
# Reviewers

## The on-push shape

### `.github/workflows/claude-review.yml`

```yaml
name: on push
```

## The on-request shape

### `.github/workflows/claude-review.yml`

```yaml
name: Review
# trigger: a comment carrying `__PHRASE__`
jobs:
  review:
    if: contains(body, '__PHRASE__')
    steps:
      - run: Read `__INSTRUCTIONS__` then a reviewer that stays silent
        needs: __PRIMARY__
```

### Human checklist

```yaml
name: not this block
```
T
  cat > "$d/$wf_c" <<'T'
name: Review
# trigger: the repo's own history, which the template does not carry
jobs:
  review:
    if: contains(body, '@claude')
    steps:
      - run: Read `.github/copilot-instructions.md` then a reviewer that stays silent
        needs: copilot
T
  cat > "$d/docs/agents/ship.md" <<'T'
### claude

Login: claude[bot]
Request: comment @claude
Fallback-for: copilot
Instructions: .github/copilot-instructions.md
T
  printf '%s' "$d"
}
# <dir>
rc_of()  { (cd "$1" && bash "$script" "$1" >/dev/null 2>&1); printf '%s' "$?"; }
out_of() { (cd "$1" && bash "$script" "$1" 2>/dev/null); }
hdr() { printf 'template-drift: %s differs from %s outside its consumer-owned regions:' "$1" "$2"; }

d=$(root clean)
check_rc "matching copies pass" 0 "$(rc_of "$d")"
check "a clean run prints nothing" "" "$(out_of "$d")"

# Pair 1: the header and the gates slot are the repo's.
d=$(root gate-drift)
sed 's/echo old/echo new/' "$d/$gate_c" > "$d/x" && mv "$d/x" "$d/$gate_c"
check_rc "a drifting non-exempt line in local-gate.sh fails" 1 "$(rc_of "$d")"
check "the first line names the copy and the template" "$(hdr $gate_c $gate_t)" "$(out_of "$d" | head -n 1)"
check "the second line is the drifting token, indented" "  copy: new;" "$(out_of "$d" | sed -n 3p)"
check "one block, not one per pair" "3" "$(out_of "$d" | wc -l | tr -d ' ')"

d=$(root gate-missing-helper)
grep -v '^put()' "$d/$gate_c" > "$d/x" && mv "$d/x" "$d/$gate_c"
check_rc "a copy missing a template helper fails" 1 "$(rc_of "$d")"

# Pair 2: the scanner fills are the repo's own, read from the copy.
d=$(root boot-drift)
sed 's/^install /uninstall /' "$d/$boot_c" > "$d/x" && mv "$d/x" "$d/$boot_c"
check_rc "a drifting line in cloud-ship-bootstrap.sh fails" 1 "$(rc_of "$d")"
check "the first line names the bootstrap pair" "$(hdr $boot_c $boot_t)" "$(out_of "$d" | head -n 1)"

d=$(root boot-other-fill)
cat > "$d/$boot_c" <<'T'
#!/usr/bin/env bash
SCANNER=trufflehog
SCANNER_INSTALL='brew install trufflehog'
install "$SCANNER"
T
check_rc "a different scanner fill passes" 0 "$(rc_of "$d")"

# Pair 3: the on-request workflow block of the reviewer scaffold.
d=$(root wf-drift)
sed 's/silent/quiet/' "$d/$wf_c" > "$d/x" && mv "$d/x" "$d/$wf_c"
check_rc "a drifting word in the workflow fails" 1 "$(rc_of "$d")"
check "the first line names the workflow pair" "$(hdr $wf_c $wf_t)" "$(out_of "$d" | head -n 1)"

d=$(root wf-reflow)
cat > "$d/$wf_c" <<'T'
name:   Review
jobs:
  review:
    if:
        contains(body, '@claude')
    steps:
      - run: Read `.github/copilot-instructions.md`
          then a reviewer
          that stays silent
        needs:
          copilot
T
check_rc "a reflowed prompt passes" 0 "$(rc_of "$d")"

d=$(root wf-comments)
{ printf '# a comment the template lacks\n'; sed 's/^# trigger.*/    # indented comment/' "$d/$wf_c"; } > "$d/x" && mv "$d/x" "$d/$wf_c"
check_rc "a comment only the copy carries, or only the template carries, passes" 0 "$(rc_of "$d")"

d=$(root wf-owned)
cat > "$d/$wf_c" <<'T'
name: Review
jobs:
  review:
    if: contains(body, '@claude')
    # >>> repo-owned
    env:
      EXTRA: yes
    # <<< repo-owned
    steps:
      - run: Read `.github/copilot-instructions.md` then a reviewer that stays silent
        needs: copilot
T
check_rc "a marked repo-owned region passes" 0 "$(rc_of "$d")"

d=$(root wf-owned-open)
sed 's/^    if: .*/&\n    # >>> repo-owned/' "$d/$wf_c" > "$d/x" && mv "$d/x" "$d/$wf_c"
check_rc "a repo-owned region never closed is tooling" 2 "$(rc_of "$d")"

d=$(root wf-no-block)
printf '# Reviewers\n' > "$d/$wf_t"
check_rc "a scaffold with no on-request workflow block is tooling" 2 "$(rc_of "$d")"

d=$(root wf-no-profile)
rm "$d/docs/agents/ship.md"
check_rc "a missing profile is tooling" 2 "$(rc_of "$d")"

# Phrase and brief come from the profile: another phrase fills the template's.
d=$(root wf-other-phrase)
sed 's/@claude/@review/' "$d/docs/agents/ship.md" > "$d/x" && mv "$d/x" "$d/docs/agents/ship.md"
check_rc "a copy still carrying the old phrase fails once the profile moves on" 1 "$(rc_of "$d")"

d=$(root missing-copy)
rm "$d/$gate_c"
check_rc "a missing copy is tooling" 2 "$(rc_of "$d")"

d=$(root two-drifts)
sed 's/echo old/echo new/' "$d/$gate_c" > "$d/x" && mv "$d/x" "$d/$gate_c"
sed 's/^install /uninstall /' "$d/$boot_c" > "$d/x" && mv "$d/x" "$d/$boot_c"
check "two drifting pairs print two blocks" "2" "$(out_of "$d" | grep -c '^template-drift:')"

check_rc "this repo's copies match their templates" 0 "$(cd "$PWD" && bash "$script" >/dev/null 2>&1; printf '%s' "$?")"

finish

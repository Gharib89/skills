#!/usr/bin/env bash
# A setup section re-run refreshes an installed Claude reviewer workflow from its
# scaffold instead of writing it only where none is installed. Three readings of
# prose, each a function so the fixture cases can break it: the re-run paragraph
# no longer files Reviewer scaffolding under "writing only where none is found or
# installed"; the item carries a compare for the `reviewer-scaffolding` section
# update-skills routes to it; and the GitHub scaffold no longer says a re-run
# skips an installed workflow or that moving pins is the consumer's own edit.
# Reads files only; no call here reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

setup=skills/setup-skills/SKILL.md
update=skills/update-skills/SKILL.md
scaffold=skills/setup-skills/reviewers/github-claude-review.md

# The blank-line-separated paragraph opening with the bold label, in full.
para() { awk -v RS= -v lbl="**$2" 'index($0, lbl) == 1' "$1"; }

# Prints "listed" when the re-run paragraph names the item in its write-only clause.
write_only_lists() {
  para "$1" 'A setup section re-run' \
    | grep -o 'writing only where none is found[^(]*([^)]*)' \
    | grep -q 'Reviewer scaffolding' && echo listed
}

# Prints "compares" when the item's paragraph carries the compare for an installed
# workflow: it names the section and holds each rule the compare keeps, so a
# sentence that mentions the words but drops a rule does not pass.
item_compares() {
  local p phrase; p=$(para "$1" 'Reviewer scaffolding')
  [ -n "$p" ] || return 0
  for phrase in '`reviewer-scaffolding`' 'installed Claude workflow' 'whole current scaffold' 'installed trigger' \
    'never guessed' 'deliberate departures' 'persist-credentials: false' 'never downgrades'; do
    grep -qF -- "$phrase" <<<"$p" || return 0
  done
  echo compares
}

fx=$(mktemp -d) || exit 2
trap 'rm -rf "$fx"' EXIT

cat > "$fx/old.md" <<'EOF'
**Reviewer scaffolding**, for each reviewer the user named that is not installed: write the files.

**A setup section re-run**, when a refresh names sections: or writing only where none is found or installed (**Coding standards**, **Reviewer scaffolding**, step 1.1's tracker doc). Write on confirm.
EOF
cat > "$fx/new.md" <<'EOF'
**Reviewer scaffolding**, for each reviewer not installed: write the files. In a setup section re-run naming `reviewer-scaffolding`, an installed Claude workflow is compared against the whole current scaffold. The shape comes from the installed trigger; a value that cannot be read is never guessed. Keep the repo's deliberate departures. Propose a pin move only where a checkout lacks `persist-credentials: false`; a refresh never downgrades.

**A setup section re-run**, when a refresh names sections: or writing only where none is found or installed (**Coding standards**, step 1.1's tracker doc). Write on confirm.
EOF
cat > "$fx/both-groups.md" <<'EOF'
**A setup section re-run**, when a refresh names sections: proposing the parts an installed Claude workflow lacks (**Reviewer scaffolding**), or writing only where none is found (**Coding standards**, **Reviewer scaffolding**, step 1.1's tracker doc). Write on confirm.
EOF
cat > "$fx/propose-only.md" <<'EOF'
**A setup section re-run**, when a refresh names sections: proposing the parts an installed Claude workflow lacks (**Reviewer scaffolding**), or writing only where none is found (**Coding standards**, step 1.1's tracker doc). Write on confirm.
EOF
cat > "$fx/dropped-rule.md" <<'EOF'
**Reviewer scaffolding**, for each reviewer not installed: write the files. In a setup section re-run naming `reviewer-scaffolding`, an installed Claude workflow is compared against the whole current scaffold. The shape comes from the installed trigger; a value that cannot be read is never guessed. Keep the repo's deliberate departures. Propose a pin move only where a checkout lacks `persist-credentials: false`.
EOF
cat > "$fx/stale-scaffold.md" <<'EOF'
The cost is that a `/setup-skills` re-run writes this workflow only where none is installed: moving them is the consumer's own edit.
EOF

check "the old paragraph lists Reviewer scaffolding as write-only" "listed" "$(write_only_lists "$fx/old.md")"
check "the new paragraph does not" "" "$(write_only_lists "$fx/new.md")"
check "an item that drops the never-downgrade rule does not compare" "" "$(item_compares "$fx/dropped-rule.md")"
check "naming the item in the propose group only is not write-only" "" "$(write_only_lists "$fx/propose-only.md")"
check "re-adding the item to the write-only group is caught beside the propose group" "listed" "$(write_only_lists "$fx/both-groups.md")"
check "the old item has no compare" "" "$(item_compares "$fx/old.md")"
check "the new item compares an installed workflow" "compares" "$(item_compares "$fx/new.md")"

check "the re-run paragraph exists to be judged" "yes" "$(para "$setup" 'A setup section re-run' | grep -q . && echo yes || echo no)"
check "the item exists to be judged" "yes" "$(para "$setup" 'Reviewer scaffolding' | grep -q . && echo yes || echo no)"

check "the re-run paragraph does not list Reviewer scaffolding as write-only" "" "$(write_only_lists "$setup")"

# The row is what sends an owner to the item, so a row with no compare behind it
# is the gap this test exists for.
row=$(grep -c '^| `reviewer-scaffolding` | \*\*Reviewer scaffolding\*\* |$' "$update")
check "update-skills still routes reviewer-scaffolding to the item" "1" "$row"
check "the item carries a compare for the section that row routes to it" "compares" "$(item_compares "$setup")"

check "the GitHub scaffold does not call moving pins the consumer's own edit" "0" "$(grep -c "consumer's own edit" "$scaffold")"
check "the GitHub scaffold does not say a re-run writes only where none is installed" "0" \
  "$(grep -c 'only where none is installed' "$scaffold")"
check "the stale wording is caught" "1" "$(grep -c "consumer's own edit" "$fx/stale-scaffold.md")"

finish

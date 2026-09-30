#!/usr/bin/env bash
# scripts/self-contained-check.sh: a skill's prose points only at material that
# installs with it. Each case builds a checkout under a fresh root and tracks one
# skill file in it, because the subject is what a derived copy carries, which is
# the tracked tree under `skills/<name>/`.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT

# <case> <path> <line>: a checkout tracking one file holding <line>; prints its path.
repo() {
  local d="$fixture/$1"
  rm -rf "$d"; mkdir -p "$d/$(dirname "$2")" || return 1
  git -C "$d" init -q || return 1
  printf '%s\n' "$3" > "$d/$2" || return 1
  git -C "$d" add -Af || return 1
  printf '%s' "$d"
}
rc_of()  { bash scripts/self-contained-check.sh "$1" >/dev/null 2>&1; printf '%s' "$?"; }
out_of() { bash scripts/self-contained-check.sh "$1" 2>/dev/null; }

# The real tree, so a leak committed here fails a case rather than leaving every
# synthetic fixture green.
check_rc "the current tree is self-contained" 0 "$(rc_of .)"

d=$(repo glossary skills/a/SKILL.md 'Vocabulary: [CONTEXT.md](https://github.com/Gharib89/skills/blob/main/CONTEXT.md).')
check_rc "a URL to a source-repo file fails" 1 "$(rc_of "$d")"
check "the message names the file, the line and the reason" \
  "skills/a/SKILL.md:1: links source-repo material by URL" "$(out_of "$d")"

d=$(repo issue-link skills/a/SKILL.md 'is to read the profile ([#367](https://github.com/Gharib89/skills/issues/367)).')
check_rc "an issue link fails" 1 "$(rc_of "$d")"

d=$(repo pr-link skills/a/reviewers/x.md 'probed on a runner, [run on #174](https://github.com/Gharib89/skills/pull/174)')
check_rc "a PR link fails" 1 "$(rc_of "$d")"

d=$(repo destination skills/a/reference/detection.md 'file an issue on [Gharib89/skills](https://github.com/Gharib89/skills/issues) asking for its entry.')
check_rc "the issue tracker as a destination passes" 0 "$(rc_of "$d")"

# Any source-repo path is material but the tracker itself, and GitHub resolves
# the owner and repo case-insensitively.
d=$(repo run-link skills/a/SKILL.md 'the [run](https://github.com/Gharib89/skills/actions/runs/1) proved it')
check_rc "a URL to an Actions run fails" 1 "$(rc_of "$d")"

d=$(repo cased skills/a/SKILL.md 'see https://github.com/gharib89/Skills/wiki/Home')
check_rc "a differently cased URL fails" 1 "$(rc_of "$d")"

d=$(repo new-issue skills/a/SKILL.md 'open [a new issue](https://github.com/Gharib89/skills/issues/new) or read https://github.com/Gharib89/skills.')
check_rc "the new-issue form and the repo root pass" 0 "$(rc_of "$d")"

d=$(repo pr-number skills/a/SKILL.md 'PR #212 is the case.')
check_rc "a bare PR number fails" 1 "$(rc_of "$d")"
check "the message names the reason" \
  "skills/a/SKILL.md:1: cites an issue or PR number" "$(out_of "$d")"

d=$(repo cased-number skills/a/SKILL.md 'Issue #12 settled it, as did pr #13.')
check_rc "a capitalised issue number fails" 1 "$(rc_of "$d")"

# A fenced block is an example, as a code span is: its numbers and links are
# the sample's, and the fence's close hands the lines after it back to prose.
d=$(repo fenced skills/a/SKILL.md "$(printf '%s\n' '```markdown' '- PR #12 [glossary](../../CONTEXT.md)' '```')")
check_rc "a number and a link inside a fence pass" 0 "$(rc_of "$d")"

d=$(repo after-fence skills/a/SKILL.md "$(printf '%s\n' '~~~' 'PR #12' '~~~' 'See PR #13.')")
check_rc "a number after a closed fence fails" 1 "$(rc_of "$d")"
check "the finding names the line after the fence" \
  "skills/a/SKILL.md:4: cites an issue or PR number" "$(out_of "$d")"

# A fence closes only on its own character at its own length or longer, so an
# example block nested in another one cannot hand the lines after it back to
# prose early, or keep them as code. Every case is red on a binary toggle except
# the longer closer and the unclosed fence, which guard what the toggle did.
d=$(repo tilde-wraps-backtick skills/a/SKILL.md "$(printf '%s\n' '~~~' '```' 'PR #12' '```' '~~~' 'See issue #13.')")
check "a tilde fence wrapping a backtick fence exempts the inner block and checks the prose after" \
  "skills/a/SKILL.md:6: cites an issue or PR number" "$(out_of "$d")"

d=$(repo tilde-wraps-open skills/a/SKILL.md "$(printf '%s\n' '~~~' '```' '~~~' 'See issue #13.')")
check_rc "a lone backtick line inside a tilde fence does not close it" 1 "$(rc_of "$d")"

d=$(repo long-wraps-short skills/a/SKILL.md "$(printf '%s\n' '````' '```' 'PR #12' '```' '````' 'See PR #13.')")
check "a four-backtick fence wrapping a three-backtick fence exempts the inner block and checks the prose after" \
  "skills/a/SKILL.md:6: cites an issue or PR number" "$(out_of "$d")"

d=$(repo long-closes skills/a/SKILL.md "$(printf '%s\n' '```' 'PR #12' '`````' 'See PR #13.')")
check "a longer run closes a shorter fence" \
  "skills/a/SKILL.md:4: cites an issue or PR number" "$(out_of "$d")"

d=$(repo info-closer skills/a/SKILL.md "$(printf '%s\n' '```' 'x' '```bash' 'y' '```' 'See PR #99.')")
check "a closing line carrying an info string does not close the fence" \
  "skills/a/SKILL.md:6: cites an issue or PR number" "$(out_of "$d")"

d=$(repo inline-triple skills/a/SKILL.md "$(printf '%s\n' '```x``` is inline code.' 'See PR #2.')")
check "triple backticks used as inline code do not open a fence" \
  "skills/a/SKILL.md:2: cites an issue or PR number" "$(out_of "$d")"

d=$(repo unclosed skills/a/SKILL.md "$(printf '%s\n' '```' 'PR #12')")
check_rc "an unclosed fence exempts the rest of the file" 0 "$(rc_of "$d")"

# A link-reference definition is a link whose target sits on its own line: the
# same target rule holds it, and a fence exempts it as it does an inline link.
d=$(repo refdef skills/a/SKILL.md "$(printf '%s\n' 'See [the glossary][g].' '' '[g]: ../../GLOSSARY.md "Glossary"')")
check_rc "a reference definition leaving the skill fails" 1 "$(rc_of "$d")"
check "the message names the line and the target" \
  "skills/a/SKILL.md:3: links outside skills/a/: ../../GLOSSARY.md" "$(out_of "$d")"

d=$(repo refdef-angle skills/a/reference/f.md '  [g]: <../../GLOSSARY.md>')
check_rc "an angle-bracketed reference definition leaving the skill fails" 1 "$(rc_of "$d")"

d=$(repo refdef-fenced skills/a/SKILL.md "$(printf '%s\n' '```markdown' '[g]: ../../GLOSSARY.md' '```')")
check_rc "a reference definition inside a fence passes" 0 "$(rc_of "$d")"

d=$(repo refdef-span skills/a/SKILL.md '[g]: `../../../GLOSSARY.md`')
check_rc "a reference destination quoted in a code span passes" 0 "$(rc_of "$d")"

d=$(repo refdef-span-label skills/a/SKILL.md '[`g`]: ../../GLOSSARY.md')
check_rc "a code span in the label does not hide the destination" 1 "$(rc_of "$d")"

d=$(repo refdef-own skills/a/SKILL.md "$(printf '%s\n' '[g]: reference/glossary.md#terms' '[w]: https://example.com/x' '[^1]: a footnote, not a definition')")
check_rc "a reference definition inside the skill, a URL and a footnote pass" 0 "$(rc_of "$d")"

# A consumer's own tracker syntax, quoted as an example, is not a citation.
d=$(repo number-example skills/a/reference/merge-gate.md 'An entry naming an issue by number (`#<n>`, such as `map issue #1`) is kept.')
check_rc "a number inside a code span passes" 0 "$(rc_of "$d")"

d=$(repo root-link skills/a/SKILL.md 'See [CONTEXT.md](../../CONTEXT.md).')
check_rc "a relative link above the skill fails" 1 "$(rc_of "$d")"
check "the message names the target" \
  "skills/a/SKILL.md:1: links outside skills/a/: ../../CONTEXT.md" "$(out_of "$d")"

d=$(repo sibling-link skills/a/SKILL.md 'See [ship](../ship/SKILL.md#process).')
check_rc "a relative link into a sibling skill fails" 1 "$(rc_of "$d")"

# A glob character in a target is a path segment, not a pattern against the
# directory the check runs in: expanded, `*` there becomes that directory's
# entries and the `..` count no longer reaches the right parent.
d=$(repo glob-link skills/a/reference/f.md 'See [x](*/../../../b/SKILL.md).')
check_rc "a glob character in a target is read literally" 1 "$(rc_of "$d")"

# A link quoted in a code span is an example, as a number there is.
d=$(repo link-example skills/a/SKILL.md 'A pointer such as `[x](../../CONTEXT.md)` dangles.')
check_rc "a link inside a code span passes" 0 "$(rc_of "$d")"

d=$(repo own-link skills/a/reference/cloud.md 'From [templates/x.sh](../templates/x.sh) and [the ladder](check-ladder.md#rungs).')
check_rc "a relative link inside the skill passes" 0 "$(rc_of "$d")"

d=$(repo changelog skills/a/CHANGELOG.md '- **a**: fix ([#378](https://github.com/Gharib89/skills/pull/378))')
check_rc "a changelog carries provenance and passes" 0 "$(rc_of "$d")"

d=$(repo outside docs/agents/ship.md 'See [ADR 0004](https://github.com/Gharib89/skills/blob/main/docs/adr/0004.md) and PR #212.')
check_rc "a file outside skills/ passes" 0 "$(rc_of "$d")"

d=$(repo untracked skills/a/SKILL.md 'Clean.'); printf 'PR #1\n' > "$d/skills/a/notes.md"
check_rc "an untracked file passes" 0 "$(rc_of "$d")"

check_rc "a root that is not a checkout is tooling" 2 "$(rc_of "$fixture")"
check_rc "a root that does not exist is tooling" 2 "$(rc_of "$fixture/absent")"

finish

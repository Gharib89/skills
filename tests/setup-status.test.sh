#!/usr/bin/env bash
# skills/setup-project/scripts/setup-status.sh: the setup status, one JSON line
# per step, read from a fixture tree. Each case builds a fully set-up consumer
# under a fresh root and breaks one place, so a failure names the row under
# test. The script runs on a PATH of its own: fakes for `gh`, `az`, `node`,
# `npx` and `bun`, which it reads only for their local answers, and links to the
# few real commands it needs, so a tool installed on this machine never answers.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
status=skills/setup-project/scripts/setup-status.sh
A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
# setup-project's own pin, read from its SKILL.md: `<source>#<sha>:<skill>`.
own=$(sed -n 's/^  composes: //p' skills/setup-project/SKILL.md)
own_src=${own%%#*}; own_sha=${own#*#}; own_sha=${own_sha%%:*}

bin=$fixture/bin sys=$fixture/sys; mkdir -p "$bin" "$sys"
for c in git jq awk grep head sed dirname cat; do ln -s "$(command -v "$c")" "$sys/$c" || exit 2; done
fake() { # <name> <script body>
  printf '#!/bin/sh\n%s\n' "$2" > "$bin/$1" && chmod +x "$bin/$1"
}
fake gh 'case "$1" in --version) echo "gh version 2.60.0 (2024-10-01)" ;;
  auth) [ -z "${FAKE_GH_SIGNED_OUT:-}" ] && echo gho_x ;; *) exit 127 ;; esac'
fake node 'echo v22.1.0'
fake npx 'echo 10.9.0'
fake bun 'echo 1.1.30'
fake az 'case "$1" in account) [ -z "${FAKE_AZ_SIGNED_OUT:-}" ] && echo "{}" ;; *) exit 127 ;; esac'

# <case>: a consumer set up end to end, every row done, and $fixture/<case>.lock
# a source lock at the versions it installed.
tree() {
  local d="$fixture/$1" s
  rm -rf "$d"; mkdir -p "$d/docs/agents" || return 1
  git -C "$d" init -q && git -C "$d" remote add origin https://github.com/o/r.git || return 1
  printf '{}\n' > "$d/package.json"
  for s in ship cloud-ship setup-skills update-skills setup-harness; do
    mkdir -p "$d/.claude/skills/$s"
    printf -- '---\nname: %s\nmetadata:\n  version: 0.2.0\n---\n' "$s" > "$d/.claude/skills/$s/SKILL.md"
  done
  printf -- '---\nname: ship\nmetadata:\n  version: 0.2.0\n  profile-schema: 4\n  composes: o/r#%s:tdd\n---\n' "$A" \
    > "$d/.claude/skills/ship/SKILL.md"
  printf -- '---\nname: setup-harness\nmetadata:\n  version: 0.2.0\n  harness-schema: 3\n---\n' \
    > "$d/.claude/skills/setup-harness/SKILL.md"
  mkdir -p "$d/.claude/skills/tdd" "$d/.claude/skills/setup-matt-pocock-skills"
  jq -n --arg A "$A" --arg osrc "$own_src" --arg osha "$own_sha" '{version: 1, skills: ({
    ship: {source: "Gharib89/skills"}, "cloud-ship": {source: "Gharib89/skills"},
    "setup-skills": {source: "Gharib89/skills"}, "update-skills": {source: "gharib89/skills"},
    "setup-harness": {source: "Gharib89/skills"}, tdd: {source: "o/r", ref: $A}}
    + {"setup-matt-pocock-skills": {source: $osrc, ref: $osha}})}' > "$d/skills-lock.json"
  for s in issue-tracker triage-labels domain; do printf '# %s\n' "$s" > "$d/docs/agents/$s.md"; done
  printf '# Harness profile\n\nSchema: 3\n' > "$d/docs/agents/harness.md"
  printf '# Ship profile\n\nSchema: 4\n' > "$d/docs/agents/ship.md"
  git -C "$d" add -A && git -C "$d" -c user.name=t -c user.email=t@t commit -qm init || return 1
  jq -n '{skills: {ship: {source: "Gharib89/skills", version: "0.2.0"},
    "setup-skills": {source: "Gharib89/skills", version: "0.2.0"},
    grilling: {source: "mattpocock/skills", ref: "'"$B"'"}}}' > "$fixture/$1.lock"
  printf '%s' "$d"
}
run()    { PATH="$bin:$sys" "$BASH" "$status" "$@" 2>/dev/null; }
states() { run "$@" | jq -r '"\(.step) \(.state)"'; }
# <step> <args>...: that step's evidence, one entry per line.
evidence() { local s=$1; shift; run "$@" | jq -r --arg s "$s" 'select(.step == $s) | .evidence[]'; }
state()  { local s=$1; shift; run "$@" | jq -r --arg s "$s" 'select(.step == $s) | .state'; }

done_rows='tools done
repo-and-remote done
installed-skills done
matts-setup done
harness done
ships-setup done
proof run'

d=$(tree full)
check "a fully set-up repo reads every row done, the proof left to the run's end" \
  "$done_rows" "$(states "$d" "$fixture/full.lock")"
check "with no source lock the rows still read, versions left uncompared" \
  "$done_rows" "$(states "$d")"
check "the evidence says the versions went uncompared" \
  "versions not compared: no source lock" "$(evidence installed-skills "$d" | grep 'not compared')"
check_rc "a readable tree exits 0" 0 "$(run "$d" "$fixture/full.lock" >/dev/null; echo $?)"

for f in issue-tracker triage-labels domain; do
  d=$(tree "no-$f"); rm "$d/docs/agents/$f.md"
  check "Matt's setup reads run with docs/agents/$f.md missing" "run" "$(state matts-setup "$d")"
  check "the evidence names docs/agents/$f.md" "docs/agents/$f.md missing" \
    "$(evidence matts-setup "$d" | grep missing)"
done

d=$(tree noharness); rm "$d/docs/agents/harness.md"
check "the harness reads run with no harness profile" "run" "$(state harness "$d")"
d=$(tree noship); rm "$d/docs/agents/ship.md"
check "Ship's setup reads run with no ship profile" "run" "$(state ships-setup "$d")"

d=$(tree oldharness); printf '# Harness profile\n\nSchema: 2\n' > "$d/docs/agents/harness.md"
check "a harness profile whose schema trails setup-harness reads re-run audit" \
  "re-run audit" "$(state harness "$d")"
check "its evidence names both schemas" "docs/agents/harness.md Schema 2, setup-harness reads 3" \
  "$(evidence harness "$d")"
d=$(tree oldship); printf '# Ship profile\n\nNo schema line\n' > "$d/docs/agents/ship.md"
check "a ship profile with no readable schema reads re-run audit" \
  "re-run audit" "$(state ships-setup "$d")"
# Near misses of the `Schema: N` line: indented, a longer token, quoted.
for line in '  Schema: 4' 'Schema: 4b' '`Schema: 4`'; do
  printf '# Ship profile\n\n%s\n' "$line" > "$d/docs/agents/ship.md"
  check "a ship profile whose schema line is '$line' reads re-run audit" "re-run audit" "$(state ships-setup "$d")"
done
# A metadata key nested deeper than the frontmatter's own is not the key.
d=$(tree nested); sed -i.bak 's/^  version: /    version: /' "$d/.claude/skills/cloud-ship/SKILL.md"
check "a version nested deeper than metadata reads unreadable" "cloud-ship version unreadable" \
  "$(evidence installed-skills "$d" | grep '^cloud-ship')"

d=$(tree behind); jq '.skills.ship.version = "0.10.0"' "$fixture/behind.lock" > "$fixture/behind2.lock"
check "a source-repo skill behind the source lock reads re-run audit" \
  "re-run audit" "$(state installed-skills "$d" "$fixture/behind2.lock")"
check "its evidence names both versions" "ship 0.2.0 behind 0.10.0" \
  "$(evidence installed-skills "$d" "$fixture/behind2.lock" | grep behind)"
# Versions compare by number, not as text: 0.10.0 is ahead of 0.9.0.
printf -- '---\nname: ship\nmetadata:\n  version: 0.10.0\n  profile-schema: 4\n  composes: o/r#%s:tdd\n---\n' "$A" \
  > "$d/.claude/skills/ship/SKILL.md"
jq '.skills.ship.version = "0.9.0"' "$fixture/behind.lock" > "$fixture/behind3.lock"
check "a copy ahead of the source lock by number is not behind" \
  "done" "$(state installed-skills "$d" "$fixture/behind3.lock")"

d=$(tree offpin); jq --arg B "$B" '.skills.tdd.ref = $B' "$d/skills-lock.json" > "$d/l" && mv "$d/l" "$d/skills-lock.json"
check "a composed skill off its pin reads re-run audit" "re-run audit" "$(state installed-skills "$d")"
check "its evidence names the ref and the pin" "tdd at o/r#$B, pinned o/r#$A" \
  "$(evidence installed-skills "$d" | grep ', pinned')"
d=$(tree forked); jq '.skills.ship.source = "other/ship"' "$d/skills-lock.json" > "$d/l" && mv "$d/l" "$d/skills-lock.json"
check "a chain skill installed from another source reads run" "run" "$(state installed-skills "$d")"
check "its evidence names the source" "ship from other/ship, not Gharib89/skills" \
  "$(evidence installed-skills "$d" | grep '^ship from')"
d=$(tree local); jq '.skills.ship.source = "."' "$d/skills-lock.json" > "$d/l" && mv "$d/l" "$d/skills-lock.json"
check "a chain skill recorded as local in a consumer reads run" "run" "$(state installed-skills "$d")"
git -C "$d" remote set-url origin git@github.com:Gharib89/skills.git
check "and as local in the source repo itself reads done" "done" "$(state installed-skills "$d")"
git -C "$d" remote set-url origin https://github.com/Gharib89/skills.git
check "and over the source repo's HTTPS origin" "done" "$(state installed-skills "$d")"
d=$(tree casedsrc); jq '.skills.tdd.source = "O/R"' "$d/skills-lock.json" > "$d/l" && mv "$d/l" "$d/skills-lock.json"
check "a composed skill whose lock source differs from its pin only in case reads done" \
  "done" "$(state installed-skills "$d")"
d=$(tree othersrc); jq '.skills.tdd.source = "x/y"' "$d/skills-lock.json" > "$d/l" && mv "$d/l" "$d/skills-lock.json"
check "a composed skill from another source at the pinned sha reads re-run audit" \
  "re-run audit" "$(state installed-skills "$d")"
cp -R skills/setup-project "$fixture/sp" && sed -i.bak '/^  composes: /d' "$fixture/sp/SKILL.md"
d=$(tree nopins); out=$(PATH="$bin:$sys" "$BASH" "$fixture/sp/scripts/setup-status.sh" "$d" 2>/dev/null); rc=$?
check_rc "setup-project's own composes line unreadable exits 2" 2 "$rc"
check "with an error object" "true" "$(jq -c 'has("error")' <<<"$out")"
d=$(tree ownpin); jq --arg B "$B" '.skills["setup-matt-pocock-skills"].ref = $B' "$d/skills-lock.json" > "$d/l" \
  && mv "$d/l" "$d/skills-lock.json"
check "setup-project's own composed skill off its pin reads re-run audit" \
  "re-run audit" "$(state installed-skills "$d")"

d=$(tree nocloud); rm -rf "$d/.claude/skills/cloud-ship"
check "a chain skill with no folder reads run" "run" "$(state installed-skills "$d")"
check "its evidence names it" "cloud-ship missing" "$(evidence installed-skills "$d" | grep missing)"
d=$(tree nolock); rm "$d/skills-lock.json"
check "no lock reads run, every chain skill missing" "run" "$(state installed-skills "$d")"

d=$(tree badlock)
printf 'not json\n' > "$fixture/bad.lock"
check_rc "a malformed source lock exits 2" 2 "$(run "$d" "$fixture/bad.lock" >/dev/null; echo $?)"
check "and prints one error object, no rows" "error" "$(run "$d" "$fixture/bad.lock" | jq -r 'keys[]')"
printf '{"skills": []}\n' > "$fixture/bad2.lock"
check_rc "a source lock whose skills is no object exits 2" 2 "$(run "$d" "$fixture/bad2.lock" >/dev/null; echo $?)"
printf '{"skills": {"ship": {"version": "latest"}}}\n' > "$fixture/bad3.lock"
check_rc "a source lock whose version is no version exits 2" 2 "$(run "$d" "$fixture/bad3.lock" >/dev/null; echo $?)"
check_rc "a source lock that cannot be read exits 2" 2 "$(run "$d" "$fixture/none.lock" >/dev/null; echo $?)"

d=$(tree noorigin); git -C "$d" remote remove origin
check "git with no origin reads the repo row run" "run" "$(state repo-and-remote "$d")"
check "its evidence names the missing origin" "no origin remote" "$(evidence repo-and-remote "$d" | grep origin)"

d=$fixture/empty; mkdir -p "$d"
check "an empty folder reads every row but the proof run" \
  "tools done
repo-and-remote run
installed-skills run
matts-setup run
harness run
ships-setup run
proof run" "$(states "$d")"
check "its repo evidence names each missing piece" "no .git
no origin remote
no stack manifest" "$(evidence repo-and-remote "$d")"

# Loose code with no git takes the same row logic as an empty folder: each
# missing piece is read on its own, and the code already there is no evidence of
# any of them.
d=$fixture/loose; mkdir -p "$d/src"; printf 'print(1)\n' > "$d/main.py"; printf 'x\n' > "$d/src/util.py"
check "loose code with no git reads the repo row run" "run" "$(state repo-and-remote "$d")"
check "its evidence names each missing piece" "no .git
no origin remote
no stack manifest" "$(evidence repo-and-remote "$d")"
d=$fixture/loose-manifest; mkdir -p "$d"; printf '{}\n' > "$d/package.json"; : > "$d/bun.lock"
check "loose code with a manifest and no git names only the git pieces" "no .git
no origin remote
manifest package.json" "$(evidence repo-and-remote "$d")"
check "and checks the stack's own tool by its lockfile" "bun 1.1.30" "$(evidence tools "$d" | grep '^bun ')"

# A stack manifest is the new project's to scaffold: a repo with history already
# has whatever stack it has, so its absence alone does not make the row run.
d=$(tree nomanifest); git -C "$d" rm -q package.json && git -C "$d" -c user.name=t -c user.email=t@t commit -qm rm
check "a repo with commits and no manifest still reads done" "done" "$(state repo-and-remote "$d")"
d=$fixture/fresh; mkdir -p "$d"; git -C "$d" init -q; git -C "$d" remote add origin https://github.com/o/r.git
check "a repo with no commits and no manifest reads run" "run" "$(state repo-and-remote "$d")"

d=$(tree signedout)
check "gh signed out reads the tools row run" "run" "$(FAKE_GH_SIGNED_OUT=1 state tools "$d")"
check "its evidence says so" "gh signed out" "$(FAKE_GH_SIGNED_OUT=1 evidence tools "$d" | grep gh)"
d=$(tree ado); git -C "$d" remote set-url origin https://dev.azure.com/o/p/_git/r
check "an Azure DevOps origin reads az in place of gh" "az signed in" "$(evidence tools "$d" | grep -E '^(az|gh)')"
check "az signed out reads the tools row run" "run" "$(FAKE_AZ_SIGNED_OUT=1 state tools "$d")"
d=$(tree uv); rm "$d/package.json"; printf '[project]\n' > "$d/pyproject.toml"; : > "$d/uv.lock"
check "a stack whose tool is missing reads the tools row run" "run" "$(state tools "$d")"
check "its evidence names the missing tool" "uv missing" "$(evidence tools "$d" | grep uv)"
# The stack's tool follows its lockfile, as setup-harness's catalog maps it, plus bun.lockb.
for pair in pyproject.toml:poetry.lock:poetry pyproject.toml:pdm.lock:pdm package.json:yarn.lock:yarn \
  package.json:package-lock.json:npm package.json:pnpm-lock.yaml:pnpm; do
  IFS=: read -r man lockf tool <<<"$pair"
  d=$(tree "lock-$tool"); rm "$d/package.json"; printf '{}\n' > "$d/$man"; : > "$d/$lockf"
  check "$man with $lockf checks $tool" "$tool missing" "$(evidence tools "$d" | grep "^$tool ")"
done
# The origin forms Ship's host detection accepts, and one it refuses.
for url in git@ssh.dev.azure.com:v3/o/p/r https://o.visualstudio.com/p/_git/r \
  o@vs-ssh.visualstudio.com:v3/o/p/r; do
  d=$(tree adoform); git -C "$d" remote set-url origin "$url"
  check "$url reads as Azure DevOps" "done az signed in" \
    "$(state repo-and-remote "$d") $(evidence tools "$d" | grep -E '^(az|gh)')"
done
d=$(tree adossh); git -C "$d" remote set-url origin ssh://u@vs-ssh.visualstudio.com:22/o/p/r
check "an Azure DevOps form Ship refuses reads the repo row run" "run" "$(state repo-and-remote "$d")"
d=$(tree gitlab); git -C "$d" remote set-url origin https://gitlab.com/o/r.git
check "an origin that is neither GitHub nor Azure DevOps reads the repo row run" "run" "$(state repo-and-remote "$d")"
check "its evidence names the origin" "origin https://gitlab.com/o/r.git: neither GitHub nor Azure DevOps" \
  "$(evidence repo-and-remote "$d" | grep '^origin')"

check_rc "no root is a usage error" 2 "$(run >/dev/null; echo $?)"
check "and answers an error object" "error" "$(run | jq -r 'keys[]')"
check_rc "a root that is no directory exits 2" 2 "$(run "$fixture/nowhere" >/dev/null; echo $?)"
# source-lock.sh: the source repo's lock with each skill it writes carrying its
# version. A fake `curl` serves $raw_dir as the raw file host.
srclock=skills/setup-project/scripts/source-lock.sh
raw_dir=$fixture/raw; mkdir -p "$raw_dir/skills/ship"
fake curl 'for a; do u=$a; done; f="$FAKE_RAW/${u#https://raw.githubusercontent.com/Gharib89/skills/main/}"
  [ -f "$f" ] && cat "$f" || exit 22'
jq -n '{version: 1, skills: {ship: {source: ".", computedHash: "x"}, tdd: {source: "o/r", ref: "'"$A"'"}}}' \
  > "$raw_dir/skills-lock.json"
printf -- '---\nname: ship\nmetadata:\n  version: 0.22.1\n---\n# ship\n' > "$raw_dir/skills/ship/SKILL.md"
fetched() { FAKE_RAW=$raw_dir PATH="$bin:$sys" "$BASH" "$srclock" "$@" 2>/dev/null; }
check "the source lock rewrites a source-. skill and carries its version, upstream entries kept" \
  '{"skills":{"ship":{"source":"Gharib89/skills","version":"0.22.1"},"tdd":{"source":"o/r","ref":"'"$A"'"}}}' \
  "$(fetched)"
check "and setup-status takes it as a source lock" "done" "$(fetched > "$fixture/fetched.lock"; d=$(tree fetched)
  state installed-skills "$d" "$fixture/fetched.lock")"
printf -- '---\nname: ship\nmetadata:\n  version: latest\n---\n' > "$raw_dir/skills/ship/SKILL.md"
check_rc "a SKILL.md with no dotted version exits 1" 1 "$(fetched >/dev/null; echo $?)"
printf -- '---\nname: ship\nmetadata:\n  version: 0.22.1-rc1\n---\n' > "$raw_dir/skills/ship/SKILL.md"
check_rc "a version with a suffix past the dotted number exits 1" 1 "$(fetched >/dev/null; echo $?)"
rm "$raw_dir/skills/ship/SKILL.md"
check_rc "a SKILL.md that cannot be fetched exits 1" 1 "$(fetched >/dev/null; echo $?)"
printf 'not json\n' > "$raw_dir/skills-lock.json"
check_rc "a lock that is not JSON exits 1" 1 "$(fetched >/dev/null; echo $?)"
check "and answers an error object" "error" "$(fetched | jq -r 'keys[]')"
check_rc "an argument is a usage error" 2 "$(fetched x >/dev/null; echo $?)"
finish

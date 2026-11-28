#!/usr/bin/env bash
# The upstream-drift workflow files its issue with the Kind label update-skills'
# title rule gives the run that ships it: `enhancement` where a skill ship
# composes drifted, `chore` where only `others` rows moved. It also drops the
# heads of skills installed from heygen-com/hyperframes before planning, so
# their daily upstream commits draw no rows. The step's script is
# lifted from the workflow and run with stub mechanics and a `gh` stub that
# records each call. No call here reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

script=$(awk '
  /^ *- name: File or update the drift issue$/ { s = 1; next }
  s && !r && /^ *run: \|$/ { r = 1; next }
  r { if ($0 == "") { print; next }
      match($0, /^ */)
      if (!ind) ind = RLENGTH
      if (RLENGTH < ind) exit
      print substr($0, ind + 1) }' .github/workflows/upstream-drift.yml)
check "the workflow carries the step" yes "$([ -n "$script" ] && echo yes || echo no)"

work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT
U=$work/cwd/skills/update-skills/scripts
mkdir -p "$U" "$work/bin" "$work/tmp"
printf '#!/usr/bin/env bash\ncat "$WORK/heads-in"\n' > "$U/heads.sh"
printf '%s\n' '{"heads":{"hyperframes":"h","media-use":"h","tdd":"t"},"unreachable":[]}' > "$work/heads-in"
printf '#!/usr/bin/env bash\njq -c . "$2" > "$WORK/heads-seen"\ncat "$PLAN"\n' > "$U/plan.sh"
printf '%s\n' '{"version":2,"skills":{"hyperframes":{"source":"heygen-com/hyperframes"},"media-use":{"source":"heygen-com/hyperframes"},"tdd":{"source":"mattpocock/skills"}}}' > "$work/cwd/skills-lock.json"
printf '#!/usr/bin/env bash\necho %s\n' "'{\"rows\":1,\"table\":\"| x |\",\"changed\":true}'" > "$U/drift-body.sh"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WORK/calls"
case "$1 $2" in "issue create") echo https://github.com/o/r/issues/7 ;; esac
STUB
chmod +x "$U"/*.sh "$work/bin/gh"

# <plan json>: runs the step on that plan; prints the `issue create` call.
create_call() {
  printf '%s\n' "$1" > "$work/plan.json"
  : > "$work/calls"
  (cd "$work/cwd" && export PATH="$work/bin:$PATH" WORK="$work" PLAN="$work/plan.json" \
     RUNNER_TEMP="$work/tmp" GITHUB_STEP_SUMMARY="$work/summary" OWNER=o REPO=o/r
   bash -e -o pipefail -c "$script" >/dev/null 2>&1) || echo "step failed"
  grep '^issue create' "$work/calls"
}

A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
drift='[{"skill":"tdd","pin":"'$A'","head":"'$B'"}]'
others='[{"skill":"hyperframes","source":"o/h","old_ref":"'$A'","head":"'$B'","install":"x"}]'

out=$(create_call '{"mode":"source","drift":[],"others":'"$others"'}')
check "only others rows file the issue as chore" "--label chore" "$(grep -o -- '--label chore' <<<"$out")"
check "only others rows file no enhancement" "" "$(grep -o -- '--label enhancement' <<<"$out")"
check "the plan reads no heygen-com/hyperframes head" '{"heads":{"tdd":"t"},"unreachable":[]}' "$(cat "$work/heads-seen")"
out=$(create_call '{"mode":"source","drift":'"$drift"',"others":'"$others"'}')
check "a drift row files the issue as enhancement" "--label enhancement" "$(grep -o -- '--label enhancement' <<<"$out")"
check "a drift row files no chore" "" "$(grep -o -- '--label chore' <<<"$out")"
out=$(create_call '{"mode":"source","others":'"$others"'}')
check "a plan with no drift array fails the step, filing nothing" "step failed" "$out"

# Once the filter leaves no head while a kept upstream was unreachable, nothing
# was checked: the step fails rather than report no drift.
printf '%s\n' '{"heads":{"hyperframes":"h"},"unreachable":[{"skill":"tdd","error":"x"}]}' > "$work/heads-in"
: > "$work/summary"
out=$(create_call '{"mode":"source","drift":[],"others":[]}')
check "only hyperframes heads with a kept upstream unreachable fails the step" "step failed" "$out"
check "that failure is the no-kept-head guard's" "No kept upstream answered: drift not checked." "$(grep -o 'No kept upstream answered: drift not checked\.' "$work/summary")"
printf '%s\n' '{"heads":{"tdd":"t"},"unreachable":[{"skill":"media-use","error":"x"}]}' > "$work/heads-in"
: > "$work/summary"
create_call '{"mode":"source","drift":[],"others":[]}' >/dev/null
check "an unreachable hyperframes skill is not named in the summary" "" "$(grep -o 'media-use' "$work/summary")"

finish

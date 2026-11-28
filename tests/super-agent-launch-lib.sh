#!/usr/bin/env bash
# Fixtures shared by the super-agent launch tests: the fake CLIs on a bare PATH,
# a fleet, ledger and quota under $tmp, and the quota_with, issue, L and reset
# helpers. Source it after tests/lib.sh and tests/super-agent-fake.sh, whose
# sa_* helpers it calls.
# shellcheck disable=SC2034 # the variables set here are read by the sourcing test
source tests/super-agent-on-machine-lib.sh
s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/tools" "$tmp/fake" "$tmp/config/super-agent"
for t in bash env jq awk sed grep cat mktemp mv rm mkdir dirname basename tr head tail date timeout sort cut find wc diff chmod cp; do
  ln -s "$(command -v $t)" "$tmp/tools/$t" || exit 2
done
# the fleet sits at its default path: record reads a remote thread over its ssh string
export PATH="$tmp/bin:$tmp/tools" SA_FAKE=$tmp/fake XDG_CONFIG_HOME=$tmp/config
sa_fake_install "$tmp/bin"
fleet=$tmp/config/super-agent/fleet.json led=$tmp/ledger.json quota=$tmp/quota.json out_f=$tmp/launch.json
repo=acme/widgets
cat > "$fleet" <<'JSON'
{"thread_ram_floor_gb": 4,
 "machines": {"home": {"cores": 8, "slots": 4, "reserve": 1, "max_load": 8, "gpu": null, "gh_logins": ["alice"]},
              "box": {"environment_id": "env-box", "ssh": "box.lan", "cores": 8, "slots": 4, "max_load": 8, "gpu": null, "gh_logins": ["alice"]}},
 "repos": {"acme/widgets": {"max_ships": 2}},
 "waivers": [{"id": "w", "condition": "Codex answers with a usage-limit notice: record it as not landed."}]}
JSON
quota_with() { # <weekly remaining> [<auth>]
  jq -cn --argjson w "$1" --arg a "${2:-ok}" '{providers: {claudeAgent: {driver: "claude", status: "available", auth: $a,
    buckets: [{id: "week", window: "weekly", remaining: $w}, {id: "five", window: "5h", remaining: 0.9}]}}}' > "$quota"
}
issue() { # <number> <title> <label>...
  local n=$1 t=$2; shift 2
  sa_route "repos/$repo/issues/$n" "$(jq -cn --arg t "$t" --argjson n "$n" '{number: $n, title: $t, state: "open", labels: ($ARGS.positional | map({name: .}))}' --args "$@")"
  sa_route "repos/$repo/issues/$n/comments" '[]'
}
L() { # <number> [<launch flags>...]: the launch call for one ticket of the repo
  local n=$1 rc k; shift
  bash "$s/launch.sh" "$repo#$n" --fleet "$fleet" --ledger "$led" --quota "$quota" --machine home --thread th-super "$@"; rc=$?
  # With $unlaunch set, a test that reads only each launch's answer drops the `launching`
  # entry it recorded, which would otherwise take the next case's slot.
  if [ -n "${unlaunch:-}" ] && [ -f "$led" ]; then
    for k in $(jq -r '.entries[] | select(.stage == "launching") | .key' "$led"); do
      bash "$s/ledger.sh" --ledger "$led" drop "$k" >/dev/null
    done
  fi
  return "$rc"
}
reset() {
  rm -f "$led" "$SA_FAKE/calls" "$SA_FAKE/on-post" "$out_f"
  sa_machine home 8 16384; sa_load 0.5 12288; sa_environments '[{"environmentId":"env-box","label":"box","status":"reachable"}]'
  sa_route user '{"login":"octo"}'; sa_route "repos/$repo" '{"default_branch":"main"}'
  sa_skill_file "$repo" .claude/skills/ship-run/SKILL.md 9.0.0
  echo 2026-11-06T12:00:00Z > "$SA_FAKE/now"
  quota_with 0.8
  sa_on_machine box.lan sa_machine box 8 32768; sa_on_machine box.lan sa_load 1 20480
}

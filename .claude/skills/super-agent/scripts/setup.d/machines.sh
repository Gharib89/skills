# shellcheck shell=bash
# shellcheck disable=SC2154  # the globals below are setup.sh's: existing, facts, proposed and the like
# Sourced by setup.sh: the linked T3 environments and the check-only machines.
#
# Every linked machine also carries `ssh`, the `user@host` or config alias the
# machine check reads it over (lib/ssh.sh). The string tested is the machine's
# --ssh, else the file's own, else the host name of its first T3 url; the test is
# one key-only `ssh <string> true` that never accepts a new host key, and the
# string is recorded only when it passes. A linked machine new to the file whose
# test fails is not added; one already in the file keeps its entry. Either is
# named in `ssh_refused`, with `unknown-host-key` for a host key ssh does not know
# (the owner connects once by hand). --check-only adds a **check-only machine**,
# `{ssh, check_only: true}` with no environment id, on the same test: the machine
# check reads it, and placement never puts work on it. The file holds no user's key.
# A linked machine whose test passed and that T3 reports reachable is then measured
# by `probe.sh` over the same string (`sa_ssh_probe`); a probe that fails or prints no
# JSON line is a warning, and the machine keeps its previous facts.

# ssh_ok <machine> <ssh string>: the key-only test; a failure is named in $ssh_refused
ssh_ok() {
  local err='not a destination: starts with -'
  ! sa_ssh_target_ok "$2" || { err=$(ssh "${sa_ssh_opts[@]}" "$2" true 2>&1 >/dev/null </dev/null) && return 0; }
  ssh_refused=$(jq -c --arg m "$1" --arg s "$2" --arg r "$(sa_ssh_reason "$err")" '. + [{machine: $m, ssh: $s, reason: (if $r == "" then "ssh failed" else $r end)}]' <<<"$ssh_refused")
  return 1
}

# linked_machines: the linked machines and the check-only ones into $facts and
# $proposed, with $ssh_refused.
linked_machines() {
  # Linked T3 environments: each is a machine this super agent may launch on. A
  # reachable one whose ssh test passed is probed over that ssh (lib/ssh.sh), an
  # unreachable one only has its reachability recorded.
  ssh_refused='[]'
  if raw=$(t3 environment list --json 2>/dev/null </dev/null) \
      && envs=$(grep '^\[' <<<"$raw" | tail -1) && jq -e 'type == "array"' <<<"$envs" >/dev/null 2>&1; then
    facts=$(jq -c --argjson e "$envs" '.machines += ([$e[] | {key: .label, value: {environment_id: .environmentId, reachable: (.status == "reachable")}}] | from_entries)' <<<"$facts")
    proposed=$(jq -c --argjson e "$envs" '.machines += ([$e[] | {key: .label, value: {probed: false, slots: 1}}] | from_entries)' <<<"$proposed")
    while IFS=$'\t' read -r label _ reachable host; do
      target=$(jq -r --arg l "$label" --arg h "${host:-$label}" --argjson g "$ssh_given" '$g[$l] // (.machines[$l].ssh | strings) // $h' <<<"$existing")
      ssh_up=false
      if ssh_ok "$label" "$target"; then
        ssh_up=true
        facts=$(jq -c --arg l "$label" --arg s "$target" '.machines[$l].ssh = $s' <<<"$facts")
      elif ! jq -e --arg l "$label" '.machines | has($l)' <<<"$existing" >/dev/null 2>&1; then
        # SSH is required for a linked machine: one new to the file is not added
        facts=$(jq -c --arg l "$label" 'del(.machines[$l])' <<<"$facts")
        proposed=$(jq -c --arg l "$label" 'del(.machines[$l])' <<<"$proposed")
        continue
      fi
      [ "$reachable" = true ] || continue
      [ "$ssh_up" = true ] || continue
      out=$(sa_ssh_probe "$target" 2>/dev/null)
      line=$(grep '^{' <<<"$out" | tail -1)
      if ! jq -e '(.cores | type) == "number" and (.ram_gb | type) == "number"' <<<"$line" >/dev/null 2>&1; then
        warn "$label: no probe line over ssh${line:+: $(jq -r '.error // empty' <<<"$line" 2>/dev/null)}"; continue
      fi
      m=$(jq -c "$machine_jq"' machine(.; $f; {})' --argjson f "$floor_gb" <<<"$line")
      first=$(jq -r --arg l "$label" '.machines[$l].probed // false | not' <<<"$existing")
      facts=$(jq -c --arg l "$label" --argjson m "$m" '.machines[$l] += $m.facts' <<<"$facts")
      proposed=$(jq -c --arg l "$label" --argjson m "$m" '.machines[$l] = $m.proposal' <<<"$proposed")
      # Slots nobody chose (never probed) give way to the computed ones.
      [ "$first" != true ] || existing=$(jq -c --arg l "$label" 'if .machines[$l] then del(.machines[$l].slots, .machines[$l].max_load) else . end' <<<"$existing")
    done < <(jq -r '.[] | [.label, .environmentId, (.status == "reachable"), ((.urls // [])[0] // "" | sub("^[a-z]+://"; "") | sub("[:/].*$"; ""))] | @tsv' <<<"$envs")
  else
    warn "t3 environment list failed: no linked machines recorded"
  fi

  while IFS= read -r label; do warn "--ssh $label: no linked machine has that name, so it was ignored"
  done < <(jq -r --argjson e "${envs:-[]}" 'keys[] | select(. as $k | [$e[].label] | index($k) | not)' <<<"$ssh_given")

  # Check-only machines: read by the machine check, never placed on.
  while IFS=$'\t' read -r label target; do
    [ -n "$label" ] || continue
    if [ "$label" = "$name" ] || [ -n "$(jq -r --arg l "$label" '.machines[$l].environment_id // empty' <<<"$facts")" ]; then
      warn "--check-only $label: this or a linked machine has that name, so it was not made check-only"; continue
    fi
    ssh_ok "$label" "$target" && facts=$(jq -c --arg l "$label" --arg s "$target" '.machines[$l] = {ssh: $s, check_only: true}' <<<"$facts")
  done < <(jq -r 'to_entries[] | [.key, .value] | @tsv' <<<"$check_only")
}

# The context floor and the calls naming what its cut took out, sourced by `scorecard
# row`: $cut is the super agent folder's `.claude/settings.json` (null when the folder
# holds none, refused by name when it is no JSON object), and $sa_jq_floor the jq defs
# the row reads over the slim transcript records.

# shellcheck disable=SC2034  # cut and sa_jq_floor are read by scorecard.sh
cut=null
[ ! -f "$(sa_home_cut_settings)" ] || cut=$(jq -c 'if type == "object" then . else error("no object") end' "$(sa_home_cut_settings)" 2>/dev/null) \
  || sa_tooling "$(sa_home_cut_settings): not a JSON object"

# `ctx`: a call's context (input, cache write, cache read). Over one transcript's
# records: `fresh_calls($day)` its first call when that falls on the day, and
# `compacted_calls($day)` the first call after each compaction summary on the day.
# `cut_call($cut)` over a tool call: true when it names what the cut took out, a
# denied tool or a tool of a denied server, a switched-off skill, or a ToolSearch
# query with any of them as a whole term.
sa_jq_floor='
  def ctx: .use.in + .use.cw + .use.cr;
  def fresh_calls($day): first(.[] | select(.u | not)) | select(.ts // "" | startswith($day));
  def compacted_calls($day): reduce .[] as $e ({after: false, out: []};
      if $e.u then (if $e.compact then .after = true else . end)
      elif .after then .out += [$e] | .after = false else . end) | .out[]
    | select(.ts // "" | startswith($day));
  def cut_call($cut): [$cut.permissions.deny[]? | strings] as $deny | [$deny[] | select(startswith("mcp__"))] as $srv
    | [$cut.skillOverrides // {} | objects | to_entries[] | select(.value == "off") | .key] as $off
    | def cut_name: . as $n | any($deny[]; . == $n) or any($srv[]; . as $p | $n | startswith($p + "__"));
    if .name == "Skill" then (.sk // "") as $k | any($off[]; . == $k)
    elif .name == "ToolSearch" then any(.q // "" | strings | splits("[\\s,]+") | sub("^(select:|\\+)"; "") | select(length > 0);
      cut_name or (. as $k | any($off[]; . == $k)))
    else .name | cut_name end;'

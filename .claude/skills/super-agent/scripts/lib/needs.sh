# A need's class, its needs-you message and its working age, sourced by `_lib.sh`:
# jq definitions spliced in front of a program after `sa_jq_norm`, so `ledger need`
# and `status` share one table and one printer.
# shellcheck disable=SC2034  # read by ledger.d/needs.sh and status.sh
sa_jq_needs='
  # The class of a reason word, null for a word not in the table. A blocking need is
  # one whose thread or queue is stopped until the owner acts; an offer is one
  # nothing waits on. `ledger need` and `ledger ack` refuse a word the table lacks.
  def need_classes: {
    "permission-hold": "blocking", "merge-gate": "blocking", "scope": "blocking", "stall-cap": "blocking",
    "fault": "blocking", "no-instance": "blocking", "no-owner-skill": "blocking", "no-project": "blocking",
    "stale-ship": "blocking", "route-ask": "blocking", "owner-steered": "blocking", "triage": "blocking",
    "daily-offer": "offer", "unqueued": "offer", "parents-done": "offer", "stale-skill": "offer",
    "pr-closed": "offer", "issue-closed": "offer", "ask-first": "offer", "owner-run": "offer",
    "verify": "offer", "cleanup": "offer"};
  def need_class: need_classes[.];
  # When the owner was first told of a need: its alert mark, or for a need 0.46.0
  # pushed (`pushed: true`, no `alerted`) its `since`.
  def need_alerted: .alerted // (if .pushed == true then .since else null end);
  # A need recorded before classes (no `class`) reads as blocking, so it is never quieter.
  def need_blocking: (.class // (.reason // "" | need_class) // "blocking") == "blocking";
  # The ticket the action of a need names: its second word.
  def need_ticket: .action | sub("[?]$"; "") | split(" ")[1] // "";
  # The action with its ticket (its second word) as a link: `owner/name#n` links as
  # written; `name#n` links to the key repo when the names match; anything else stays text.
  def need_action: .key as $k | need_ticket as $t | (.action | sub("[?]$"; "") | split(" ")) as $w
    | (if ($t | test("^[^/#\\s]+/[^/#\\s]+#[0-9]+$")) then $t | sub("#"; "/issues/")
       elif ($t | test("^[^/#\\s]+#[0-9]+$")) and ($k | test("^[^/#]+/[^/#]+#[0-9]+$"))
         and ($t | sub("#.*"; "") | norm_repo) == ($k | sub("#.*"; "") | sub("^[^/]*/"; "") | norm_repo)
       then ($k | sub("#.*"; "")) + "/issues/" + ($t | sub("^.*#"; ""))
       else null end) as $path
    | if $path == null then $w | join(" ")
      else [$w[0], "[\($t)](https://github.com/\($path))"] + $w[2:] | join(" ") end;
  # One need as the needs-you message prints it: the question (bold when blocking,
  # behind `Offer:` when not), a `Why:` line, then its options from 1, the first
  # recommended, or `Answer in [its thread](…).` A need recorded before these fields
  # prints its action alone.
  def need_text: (need_action + "?") as $q
    | [if need_blocking then "**\($q)**" else "Offer: \($q)" end]
    + (if .why == null then [] else ["Why: " + (.why | if test("[.!?]$") then . else . + "." end)] end)
    + (if .answer_in != null then ["Answer in [its thread](\(.answer_in))."]
       else [(.options // []) | to_entries[] | "\(.key + 1). \(.value.label)"
         + (if .key == 0 then " (recommended)" else "" end)
         + (if .value.consequence then ": \(.value.consequence)" else "" end)] end)
    | join("\n");
  # Every open need in full, blocking first, each set apart by a blank line.
  def needs_text: [(map(select(need_blocking)) + map(select(need_blocking | not)))[] | need_text] | join("\n\n");
  # Seconds from epoch $from to epoch $to that fall on a day of $week (weekday numbers,
  # 0 Sunday) in local time, counted an hour at a time.
  def working_seconds($from; $to; $week):
    [range($from; $to; 3600) | . as $h
      | select($week | index($h | strflocaltime("%w") | tonumber)) | [3600, $to - $h] | min] | add // 0;
'

# sa_work_week <fleet>: the fleet file's `work_week` as JSON (Mon to Fri when it has
# none), or a refusal naming the file. `status` and `schedules` read it.
sa_work_week() {
  jq -ec '(if .work_week == null then [1,2,3,4,5] else .work_week end)
    | select(type == "array" and length > 0 and length == (unique | length) and all(type == "number" and . >= 0 and . <= 6 and . == floor))' "$1" 2>/dev/null \
    || sa_tooling "$1: not JSON, or work_week is not a non-empty list of distinct weekday numbers 0 to 6"
}

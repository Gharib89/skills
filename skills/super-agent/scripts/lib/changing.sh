# The changing-call patterns the scorecard's wake count and the observe hook share,
# sourced by `_lib.sh`: jq definitions, spliced in front of a program. A call these
# miss counts as changing nothing, the limit the state guard admits to as well.
# shellcheck disable=SC2034  # read by scorecard.sh and observe.sh
sa_jq_changing='
  # Every `ledger.sh` subcommand that writes.
  def ledger_verbs: ["add", "adopt", "set", "rethread", "ruling", "pin", "migrate-rulings", "wait", "unwait", "need",
    "pushed", "unneed", "limit", "unlimit", "pause", "unpause", "drop", "reset-stalls", "self"];
  def ledger_write($verbs): "ledger\\.sh[^|;&\\n]*?\\s(\($verbs | join("|")))\\b";
  # The scripts that act: the ones that launch, claim, remove, merge, clean up, take
  # in or hand over (`worktree.sh` counts only its `remove` verb).
  def acting_scripts: ["launch\\.sh", "claim\\.sh", "worktree\\.sh[^|;&\\n]*\\sremove", "merge\\.sh", "cleanup\\.sh",
    "intake\\.sh", "handover\\.sh"];
  # The `gh` and `git` calls that write.
  def host_writes: ["\\bgh\\s+(issue|pr)\\s+(edit|close|comment|create|reopen|merge|review|ready)",
    "\\bgh\\s+api\\b[^|;&\\n]*(-X|--method)\\s*(POST|PATCH|PUT|DELETE)", "\\bgh\\s+api\\b[^|;&\\n]*\\s-[fF]\\s",
    "\\bgit\\s+(commit|push|merge|worktree\\s+(add|remove)|branch\\s+-[dD])"];
'

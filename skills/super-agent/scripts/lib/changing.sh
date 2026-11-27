# The changing-call patterns the scorecard's wake count and the observe hook share,
# sourced by `_lib.sh`: jq definitions, spliced in front of a program. A call these
# miss counts as changing nothing, the limit the state guard admits to as well.
# shellcheck disable=SC2034  # read by scorecard.sh and observe.sh
sa_jq_changing='
  # Every `ledger.sh` subcommand that writes.
  def ledger_verbs: ["add", "adopt", "set", "rethread", "ruling", "pin", "migrate-rulings", "wait", "unwait", "need",
    "unneed", "ack", "limit", "unlimit", "take", "tell", "drop", "reset-stalls", "self"];
  # The verb sits right after `ledger.sh` and its `--ledger <file>`, so a verb word inside the
  # `--action` text of a need does not match.
  def ledger_write($verbs): "ledger\\.sh(\\s+--ledger\\s+(\"[^\"]*\"|\\x27[^\\x27]*\\x27|(\\\\.|\\S)+))?\\s+(\($verbs | join("|")))\\b";
  # The scripts that act: the ones that launch, claim, remove, merge, clean up, take
  # in or hand over (`worktree.sh` counts only its `remove` verb). A script counts
  # when it is run (first word, after `bash`/`sh` or a pipe or `;`), not when its
  # name is only read or passed `--help`.
  def acting_scripts: ["launch", "claim", "merge", "cleanup", "intake", "handover"]
    | map("(^|[;&|(]\\s*|\\b(bash|sh)\\s+)\\S*" + . + "\\.sh(?!\\S)(?!\\s+(-h|--help)\\b)")
    + ["worktree\\.sh[^|;&\\n]*\\sremove"];
  # The `gh` and `git` calls that write.
  def host_writes: ["\\bgh\\s+(issue|pr)\\s+(edit|close|comment|create|reopen|merge|review|ready)",
    "\\bgh\\s+api\\b[^|;&\\n]*(-X|--method)\\s*(POST|PATCH|PUT|DELETE)", "\\bgh\\s+api\\b[^|;&\\n]*\\s-[fF]\\s",
    "\\bgit\\s+(commit|push|merge|worktree\\s+(add|remove)|branch\\s+-[dD])",
    "\\bt3\\s+thread\\s+(send|launch|interrupt)"];
'

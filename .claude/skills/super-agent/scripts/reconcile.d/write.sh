# The one write `reconcile` makes, sourced by it. What this run changed between
# the ledger it read ($read_doc) and its own copy ($doc) is applied to the ledger
# as it stands now, through `sa_update`, so a write another script made while
# this run read T3 and GitHub is kept: each entry field this run changed, unless
# the entry was rethreaded or replaced meanwhile (its thread or `launched_at`
# moved); each waiting row it dropped; each key it added to `parents_offered` or
# `unqueued_offered`. It leaves the written ledger in $doc.

# shellcheck disable=SC2154  # read_doc, doc, ledger and sa_jq_norm come from reconcile.sh and _lib.sh

reconcile_write() {
  # The two documents go in as files: one argument over 128 KiB (MAX_ARG_STRLEN) fails.
  sa_update "$ledger" "$sa_jq_norm"'$read[0] as $r | $ours[0] as $o
    | reduce ($o.entries | keys_unsorted[]) as $k (.;
        $r.entries[$k] as $was
        | if .entries[$k] != null and .entries[$k].thread == $was.thread and .entries[$k].launched_at == $was.launched_at
          then reduce ($o.entries[$k] | to_entries[] | select(.value != $was[.key])) as $f (.; .entries[$k][$f.key] = $f.value)
          else . end)
    | ([($r.waiting // [])[].key] - [($o.waiting // [])[].key]) as $gone
    | if ($gone | length) > 0 then .waiting |= map(select(.key | norm_repo | IN($gone[] | norm_repo) | not)) else . end
    | reduce ("parents_offered", "unqueued_offered") as $f (.;
        (($o[$f] // []) - ($r[$f] // []) - (.[$f] // [])) as $new
        | if ($new | length) > 0 then .[$f] = ((.[$f] // []) + $new) else . end)' \
    --slurpfile read <(printf '%s\n' "$read_doc") --slurpfile ours <(printf '%s\n' "$doc")
}

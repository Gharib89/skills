# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # variables set by the sourcing script
# Checks 7 to 9 of scripts/contract-check.sh, sourced by it: they share its variables.
# 7. Every setup-harness catalog entry keeps the entry format its README fixes:
# `## Signals` first, its labels per kind, roles from the fixed set, and every
# `###` tool block carrying every required label. Detection reads only the
# Signals blocks and a run reads the rest by label, so an entry missing one is
# a stack the skill silently half-knows. A `Route:` carries its `Blocked:`
# clause, so a run can tell "nothing is blocked" from "nobody looked". A file
# kind takes no turn rung (it has no project to typecheck or test), and only a
# file kind is claimed by Names: or Paths:, and only a stack carries Library:.
# A tool's Files: is a subset of the entry's Extensions:, since it narrows the
# files the entry claims. Browser
# and public-API tools run on `full` only, and a language server sits on no
# rung, takes no hook and is `Local-only:` with its reason, because it answers
# Claude's `LSP` calls rather than a check and no cloud session starts one.
harness=$skills/setup-harness
if [ -d "$harness/catalog" ]; then
  for entry in "$harness"/catalog/*.md; do
    [ "${entry##*/}" = README.md ] && continue
    awk -v f="$entry" '
    function bad(m) { print "catalog " f ": " m; rc = 1 }
    function close_tool(  i) {
      if (tool == "") return
      for (i = 1; i <= nt; i++) if (!(tl[i] in got)) bad("### " tool ": missing " tl[i] ":")
      if (role == "language server" && !("Local-only" in got)) bad("### " tool ": a language server is Local-only:")
      tool = ""; delete got
    }
    function close_signals(  i, n, want) {
      if (!signals) return
      want = kind == "file kind" ? "Kind|Names|Paths|Extensions|Shebangs" : "Kind|Manifest|Lockfile|Workspace|Extensions|Shebangs|Runtime version|Library"
      n = split(want, w, "|")
      for (i = 1; i <= n; i++) if (!(w[i] in sig)) bad("## Signals: missing " w[i] ":")
      if (kind != "stack" && kind != "file kind") bad("## Signals: Kind: want stack or file kind, got " kind)
      if (kind == "stack") { if ("Names" in sig) bad("## Signals: Names: is a file kind\047s"); if ("Paths" in sig) bad("## Signals: Paths: is a file kind\047s") }
      if (kind == "file kind" && ("Library" in sig)) bad("## Signals: Library: is a stack\047s")
      signals = 0
    }
    BEGIN {
      nt = split("Publisher|Tier|Evidence|Rung|Run|Hook|Pin|Route|Constraints|Traps", tl, "|")
      roles = "|lint|format|typecheck|test runner|affected tests|language server|browser|public API|"
    }
    /^## / {
      close_tool(); close_signals()
      role = substr($0, 4)
      if (!headings++) { if (role == "Signals") signals = 1; else bad("first ## heading is not ## Signals"); next }
      if (index(roles, "|" role "|") == 0) bad("## " role ": not a role")
      else if (kind == "file kind" && role != "lint" && role != "format") bad("## " role ": a file kind carries lint and format only")
      next
    }
    /^### / { close_tool(); tool = substr($0, 5); next }
    /^[A-Z][A-Za-z -]*: / || /^[A-Z][A-Za-z -]*:$/ {
      label = substr($0, 1, index($0, ":") - 1); v = substr($0, length(label) + 3)
      if (signals) { sig[label] = 1; if (label == "Kind") kind = v; if (label == "Extensions") exts = " " v " "; next }
      if (tool == "") next
      got[label] = 1
      if (label == "Route" && v != "None." && v !~ /^`[^`]+`; Blocked: /) bad("### " tool ": Route: want `<install>`; Blocked: <routes> | None., or None.")
      if (label == "Hook" && role == "language server" && v != "None.") bad("### " tool ": a language server takes Hook: None.")
      if (label == "Hook" && role != "language server" && v == "None.") bad("### " tool ": Hook: None. is for a language server only")
      if (label == "Local-only" && v == "") bad("### " tool ": Local-only: wants its reason")
      if (label == "Files") { n = split(v, fx, " "); for (i = 1; i <= n; i++) if (index(exts, " " fx[i] " ") == 0) bad("### " tool ": Files: " fx[i] " is not in Extensions:") }
      if (label != "Rung") next
      if (role == "language server") { if (v != "None.") bad("### " tool ": a language server takes Rung: None.") }
      else if (v != "edit" && v != "turn" && v != "full") bad("### " tool ": Rung: want edit, turn or full, got " v)
      else if (kind == "file kind" && v == "turn") bad("### " tool ": a file kind takes no turn rung")
      else if ((role == "browser" || role == "public API") && v != "full") bad("### " tool ": " role " is full only")
    }
    END { close_tool(); close_signals(); if (!headings) bad("first ## heading is not ## Signals"); exit rc }
    ' "$entry" || rc=1
  done
fi

# 8. setup-skills reads two lines of a harness profile with no schema check,
# in its harness detection and in its cloud bootstrap template, `Location:`
# under `## Check entry point` and `Setup:` under `## Cloud`, so they are
# frozen across every harness schema:
# renaming either is a major of both skills in one PR. The profile template is
# where a rename would start.
if [ -d "$harness" ]; then
  tmpl=$harness/templates/harness-profile.md
  for pair in "Check entry point:Location" "Cloud:Setup"; do
    awk -v h="## ${pair%%:*}" -v l="${pair#*:}: " '
      /^## / { in_h = ($0 == h); next }
      in_h && index($0, l) == 1 { found = 1 }
      END { exit !found }' "$tmpl" 2>/dev/null \
      || { printf 'harness profile template: ## %s has no %s: line\n' "${pair%%:*}" "${pair#*:}"; rc=1; }
  done
fi

# 9. The harness schema number sits in four places, moved together by the
# harness bump rule in docs/contributing/standards/release.md: the skill's metadata.harness-schema, the
# template's Schema: line, the checker's schema= literal and the doc's own
# `## Schema <n>` entry. One moved alone ships a template its own checker
# refuses, or a re-run that migrates by an entry that is not there. Each read
# takes the first match before any body heading, as profile-schema-check.sh
# does, and a file it cannot read is tooling rather than drift.
if [ -d "$harness" ]; then
  doc=$harness/harness-schema.md
  meta=$(awk '/^# /{exit} /^  harness-schema: /{print $2; exit}' "$harness/SKILL.md") \
    || { printf 'cannot read %s\n' "$harness/SKILL.md" >&2; exit 2; }
  line=$(awk '/^## /{exit} /^Schema: /{print $2; exit}' "$harness/templates/harness-profile.md") \
    || { printf 'cannot read %s\n' "$harness/templates/harness-profile.md" >&2; exit 2; }
  lit=$(awk -F= '/^schema=/{print $2; exit}' "$harness/scripts/harness-profile-check.sh") \
    || { printf 'cannot read %s\n' "$harness/scripts/harness-profile-check.sh" >&2; exit 2; }
  grep -qxF "## Schema $meta" "$doc"; st=$?
  [ "$st" -le 1 ] || { printf 'cannot search %s\n' "$doc" >&2; exit 2; }
  entry=missing
  [ "$st" -eq 0 ] && entry=present
  if [ -z "$meta" ] || [ "$meta" != "$line" ] || [ "$meta" != "$lit" ] || [ "$entry" = missing ]; then
    printf "harness schema disagrees: SKILL.md metadata.harness-schema %s, templates/harness-profile.md Schema: %s, scripts/harness-profile-check.sh schema=%s, harness-schema.md entry '## Schema %s' %s\n" \
      "${meta:-none}" "${line:-none}" "${lit:-none}" "${meta:-none}" "$entry"
    rc=1
  fi
fi


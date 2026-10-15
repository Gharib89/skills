#!/usr/bin/env bash
# PROTOTYPE, throwaway: render the owner's clones, one GPU job at a time (#676).
set -u
cd "$(dirname "$0")/.." || exit
: > clone/runs.jsonl
REF=clone/ref/owner.wav TXT=$(cat clone/ref/owner.txt)
.venv-habibi/bin/python clone.py habibi "$REF" "$TXT" ar-clone-habibi-egy > raw/log-clone-habibi.txt 2>&1; tail -n 1 raw/log-clone-habibi.txt | tee -a clone/runs.jsonl
for m in namaa oddadmix; do
  .venv-chatterbox/bin/python clone.py $m "$REF" "$TXT" ar-clone-$m > raw/log-clone-$m.txt 2>&1; tail -n 1 raw/log-clone-$m.txt | tee -a clone/runs.jsonl
done

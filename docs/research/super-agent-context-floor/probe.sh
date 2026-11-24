#!/usr/bin/env bash
# probe.sh <label> <cwd> [claude flags...]: one headless Opus 5.5 call from <cwd>; prints the first call's context.
d=$(cd "$(dirname "$0")" && pwd); label=$1; cwd=$2; shift 2
cd "$cwd" && timeout 120 env -u T3CODE_THREAD_ID claude -p --model claude-opus-5-5 --max-turns 1 --output-format json "$@" 'Reply with the single word ok.' > "$d/probe-$label.json" 2>"$d/probe-$label.err" </dev/null
jq -c --arg l "$label" '{l:$l, ctx:(.usage.iterations[0]|.input_tokens+.cache_read_input_tokens+.cache_creation_input_tokens), cr:.usage.iterations[0].cache_read_input_tokens, turns:.num_turns, sid:.session_id, err:.is_error}' "$d/probe-$label.json"

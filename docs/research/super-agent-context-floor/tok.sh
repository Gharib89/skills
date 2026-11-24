#!/usr/bin/env bash
# tok.sh <file>: tokens of a file's text as one user message, by the API's own usage on a near-empty request.
f=$(realpath "$1"); d=$(cd "$(dirname "$0")" && pwd); cd "$d/empty" || exit 1
timeout 90 env -u T3CODE_THREAD_ID claude -p --model claude-opus-5-5 --system-prompt "." --tools "" --strict-mcp-config --setting-sources "" \
  --disable-slash-commands --max-turns 1 --output-format json < "$f" 2>/dev/null \
  | jq -c '{in:(.usage.iterations[0]|.input_tokens+.cache_read_input_tokens+.cache_creation_input_tokens), out:.usage.output_tokens, turns:.num_turns, err:.is_error, models:(.modelUsage|keys)}'

#!/usr/bin/env bash
# A fake `gh` on PATH, for the tests whose subject is the GitHub adapter's REST
# wrapper or one of the writes built on it. Sourced, never run:
#
#   bin=$(mktemp -d); trap 'rm -rf "$bin"' EXIT
#   source tests/gh-fake.sh; gh_fake_install "$bin"
#   gh_reset; export GH_STATUS_SEQ="500 200"
#   ... call the adapter ...
#   gh_attempts; gh_body_of 2
#
# `GH_STATUS_SEQ` is the HTTP status per attempt, the last one repeating, so
# "500 200" is one outage then a success and "500" is a burst. `none` is a call
# that never got an HTTP answer, where gh prints no header block at all.
#
# The fake models the three things the adapter depends on: `--input` resolves
# from stdin or a file the way gh's does, a failing attempt drains stdin before
# it exits (which is what empties the pipe for a retry, the #108 bug), and `-i`
# adds the CRLF header block the status is read from. `GH_BODY` is the response
# body, so a case can hand back the shape `--paginate` produces: a second header
# block after a blank line.
gh_fake_install() { # <dir>
  export GH_LOG=$1/calls
  cat > "$1/gh" <<'FAKE'
#!/usr/bin/env bash
input="" prev="" include=""
for a in "$@"; do
  case $a in
    --input=*) input=${a#--input=} ;;
    -i|--include) include=1 ;;
    *) [ "$prev" = --input ] && input=$a ;;
  esac
  prev=$a
done
case $input in
  "") body="" ;;
  -)  body=$(cat) ;;
  *)  body=$(cat "$input") ;;
esac
n=$(( $(cat "$GH_LOG.n" 2>/dev/null || echo 0) + 1 ))
printf '%s' "$n" > "$GH_LOG.n"
printf '%s\t%s\n' "$n" "$body" >> "$GH_LOG"
status=200 i=0
for s in ${GH_STATUS_SEQ:-200}; do i=$((i + 1)); status=$s; [ "$i" -ge "$n" ] && break; done
[ "$status" = none ] && { echo "gh: connection refused" >&2; exit 1; }
if [ -n "$include" ]; then
  printf 'HTTP/2.0 %s Some Reason\r\n' "$status"
  printf 'Content-Type: application/json\r\n'
  printf '\r\n'
fi
[ "$status" -ge 400 ] && { echo "gh: unexpected end of JSON input" >&2; exit 1; }
printf '%s\n' "${GH_BODY:-ok}"
exit 0
FAKE
  chmod +x "$1/gh"
  PATH=$1:$PATH
}
gh_reset()    { : > "$GH_LOG"; printf '0' > "$GH_LOG.n"; }
gh_attempts() { cat "$GH_LOG.n"; }
gh_body_of()  { awk -F'\t' -v n="$1" '$1 == n { print $2 }' "$GH_LOG"; }

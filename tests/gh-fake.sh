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
# block after a blank line. With `-i` it comes back on a failing status too,
# because `-i` prints the whole response and an error carries one.
#
# `GH_ROUTES` set to a directory answers each call by its endpoint instead, for
# a script that makes several different reads: `gh_route <endpoint> <body>`
# writes the body one endpoint answers (an empty body too), matched with the
# call's query string ignored, and an endpoint with no route fails the way
# gh's 404 does. A call with `-X`/`--method` other than GET is matched by
# `<METHOD> <endpoint>`, so a read and a write of one endpoint answer apart.
# `gh_args` lists each call's arguments, one line per call.
gh_fake_install() { # <dir>
  export GH_LOG=$1/calls
  cat > "$1/gh" <<'FAKE'
#!/usr/bin/env bash
input="" prev="" include="" endpoint="" method=GET
for a in "${@:2}"; do
  case $prev:$a in
    --input:*) input=$a ;;
    -X:*|--method:*) method=$a ;;
    *:--input=*) input=${a#--input=} ;;
    *:-i|*:--include) include=1 ;;
    *:-*|-q:*|--jq:*|-H:*|--header:*|-f:*|--raw-field:*|-F:*|--field:*) ;;
    *) [ -n "$endpoint" ] || endpoint=$a ;;
  esac
  prev=$a
done
printf '%s\n' "$*" >> "$GH_LOG.args"
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
out=${GH_BODY:-ok}
if [ -n "${GH_ROUTES:-}" ] && [ "$status" -lt 400 ]; then
  route=${endpoint%%\?*}
  [ "$method" = GET ] || route="$method $route"
  route=$GH_ROUTES/${route//\//_}
  [ -f "$route" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
  out=$(cat "$route")
fi
if [ -n "$include" ]; then
  printf 'HTTP/2.0 %s Some Reason\r\n' "$status"
  printf 'Content-Type: application/json\r\n'
  printf '\r\n'
fi
if [ "$status" -ge 400 ]; then
  [ -n "$include" ] && [ -n "${GH_BODY:-}" ] && printf '%s\n' "$GH_BODY"
  echo "gh: unexpected end of JSON input" >&2
  exit 1
fi
printf '%s\n' "$out"
exit 0
FAKE
  chmod +x "$1/gh"
  PATH=$1:$PATH
}
gh_reset()    { : > "$GH_LOG"; : > "$GH_LOG.args"; printf '0' > "$GH_LOG.n"; }
gh_route()    { mkdir -p "$GH_ROUTES"; printf '%s\n' "$2" > "$GH_ROUTES/${1//\//_}"; } # <endpoint> <body>
gh_args()     { cat "$GH_LOG.args" 2>/dev/null; }
gh_attempts() { cat "$GH_LOG.n"; }
gh_body_of()  { awk -F'\t' -v n="$1" '$1 == n { print $2 }' "$GH_LOG"; }

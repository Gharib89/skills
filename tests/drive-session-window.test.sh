#!/usr/bin/env bash
# `window` reports whether a render, calibration or full check is running, so
# the supervisor never hands the quiet window on while one is. Driven over a
# fake `ps` on PATH that prints a canned process table (a real table would make
# the nothing-running cases depend on what the machine happens to run), plus one
# case over a real stub process under the real `ps`.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

w=skills/drive-session/scripts/window.sh
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"; [ -z "${stub:-}" ] || kill "$stub" 2>/dev/null' EXIT
mkdir -p "$tmp/bin"
cat > "$tmp/bin/ps" <<'FAKE'
#!/usr/bin/env bash
[ "$*" = "-eo pid=,args=" ] || { echo "fake ps: unexpected call: $*" >&2; exit 1; }
cat "$PS_TABLE"
[ -z "${PS_FAIL:-}" ]
FAKE
chmod +x "$tmp/bin/ps"
real_path=$PATH
export PS_TABLE=$tmp/table

# window <table line>...: runs it over a table of those lines, leaving $out and $rc.
window() {
  printf '%s\n' "$@" > "$PS_TABLE"
  out=$(PATH="$tmp/bin:$real_path" bash "$w" 2>"$tmp/err"); rc=$?
}
noise=(
  "   1 /sbin/init"
  " 900 claude --model sonnet"
  " 901 vim skills/explainer-video/maintainer/real-render.mjs"
  " 902 bash scripts/check.sh turn"
  " 903 bash scripts/check.sh edit a.sh b.sh"
  " 904 node skills/explainer-video/maintainer/real-render.test.mjs"
  " 905 grep -r hyperframes skills"
  " 906 node -r dotenv/config skills/explainer-video/maintainer/real-render.test.mjs"
  " 907 /bin/bash -c source /tmp/snap.sh && eval 'grep -rn real-render.mjs skills'"
  " 908 /bin/zsh -c source /tmp/snap.sh && eval 'git log -S hyperframes | head' < /dev/null"
  " 909 bash -c vim skills/explainer-video/maintainer/calibrate-rates.mjs"
)

window "${noise[@]}"
check_rc "nothing running exits 0" 0 "$rc"
check "and answers an empty list" '{"running":[]}' "$out"
# An empty table is a failed read, not a verdict: a live one always lists ps itself.
window
check_rc "an empty process table exits 2" 2 "$rc"
check "and says the table could not be read" "window: cannot read the process table" "$(jq -r .error <<<"$out")"
# So is a table `ps` printed before it failed.
PS_FAIL=1 window "${noise[@]}"
check_rc "a ps that fails after printing part of a table exits 2" 2 "$rc"
check "and says the table could not be read too" "window: cannot read the process table" "$(jq -r .error <<<"$out")"

# <case>|<process line>|<name the answer carries>
running=(
  "a real render|4101 node skills/explainer-video/maintainer/real-render.mjs|real-render"
  "a section render|4101 node skills/explainer-video/maintainer/real-render-sections.mjs|real-render"
  "a hyperframes render|4101 node /home/u/.cache/x/node_modules/.bin/hyperframes render proj|hyperframes"
  "a hyperframes render as the explainer-video cache runs it|4101 /usr/bin/node /home/u/.cache/explainer-video/node/b1fb/node_modules/hyperframes/bin/hyperframes.mjs render --strict --fps 30 -o /tmp/real-render-x/whole-1.mp4|hyperframes"
  "a hyperframes render under npx|4101 npx hyperframes render|hyperframes"
  "a hyperframes render by its package path|4101 node /home/u/.cache/x/node_modules/hyperframes/dist/cli.js render|hyperframes"
  "a calibration|4101 node skills/explainer-video/maintainer/calibrate-rates.mjs|calibrate"
  "a full check|4101 bash scripts/check.sh full|check.sh full"
  "a full check run by its path|4101 /home/u/skills/scripts/check.sh full|check.sh full"
  "a full check under a shell -c|4101 bash -c scripts/check.sh full|check.sh full"
  "a render behind an interpreter flag that takes a value|4101 node -r dotenv/config skills/explainer-video/maintainer/real-render.mjs|real-render"
  "a calibration behind a long flag and its value|4101 node --import tsx skills/explainer-video/maintainer/calibrate-rates.mjs|calibrate"
  "a render behind env|4101 env FOO=1 node skills/explainer-video/maintainer/real-render.mjs|real-render"
  "a full check behind timeout|4101 timeout 600 bash scripts/check.sh full|check.sh full"
  "a calibration behind nohup|4101 nohup node skills/explainer-video/maintainer/calibrate-rates.mjs|calibrate"
  "a render a Claude Code shell call runs|4101 /bin/bash -c source /tmp/snap.sh && eval 'node skills/explainer-video/maintainer/real-render.mjs' < /dev/null|real-render"
  "a render after a grep in the same shell call|4101 /bin/bash -c grep -c x f && node skills/explainer-video/maintainer/real-render.mjs|real-render"
  "a render run from a path with a space|4101 node /tmp/window space/real-render.mjs|real-render"
  "a calibration run from a path with a space|4101 /usr/bin/node /tmp/my skills/calibrate-rates.mjs|calibrate"
  "a hyperframes render run from a path with a space|4101 node /tmp/my cache/node_modules/hyperframes/bin/hyperframes.mjs render|hyperframes"
  "a full check run from a path with a space|4101 bash /home/u/my skills/scripts/check.sh full|check.sh full"
)
for r in "${running[@]}"; do
  IFS='|' read -r name line want <<<"$r"
  window "${noise[@]}" "$line"
  check_rc "$name: exit 1" 1 "$rc"
  check "$name: the answer names the process and its pid" \
    "a render, calibration or check is running: $want (pid 4101)" "$(jq -r .error <<<"$out")"
  check "$name: the list holds that one process" "[{\"pid\":4101,\"name\":\"$want\"}]" "$(jq -c .running <<<"$out")"
  check "$name: it says the same on stderr" "$(jq -r .error <<<"$out")" "$(cat "$tmp/err")"
done

window "${noise[@]}" "4101 bash scripts/check.sh full" "4102 node skills/explainer-video/maintainer/real-render.mjs"
check "every running process is listed, in table order" \
  '[{"pid":4101,"name":"check.sh full"},{"pid":4102,"name":"real-render"}]' "$(jq -c .running <<<"$out")"
check "and each is named in the error" \
  "a render, calibration or check is running: check.sh full (pid 4101), real-render (pid 4102)" "$(jq -r .error <<<"$out")"

# The real `ps` sees a real process: `exec -a` gives a sleep the name a render has.
( exec -a real-render sleep 60 ) & stub=$!
out=$(bash "$w" 2>/dev/null); rc=$?
check_rc "a real stub process is seen" 1 "$rc"
check "and named by its pid" "real-render $stub" "$(jq -r '.running[] | select(.pid == '"$stub"') | "\(.name) \(.pid)"' <<<"$out")"
kill "$stub"; wait "$stub" 2>/dev/null; stub=

# The contract every script keeps.
out=$(bash "$w" --help 2>"$tmp/err"); rc=$?
check "--help opens with its usage line" "usage: window" "$(sed -n 1p <<<"$out")"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"
out=$(bash "$w" now 2>/dev/null); rc=$?
check_rc "an argument is a usage error, exit 2" 2 "$rc"
check "and the error is the usage line" "usage: window" "$(jq -r .error <<<"$out")"

finish

#!/usr/bin/env bash
# Probe for "Web-session probe of browser routes" (#359). Run once locally as
# the control, then in a Claude Code on the web session started on branch
# research/harness-browser-routes. Prints a Markdown report to stdout and to
# $PROBE_LOG. Section numbers follow the ticket's Question.
# Read-only against the repo and tracker. Starting dockerd and apt installs run
# only when CLAUDE_CODE_REMOTE=true. PROBE_SKIP_CARGO=1 skips section 7.
set -u
S=/tmp/browser-probe
LOG=${PROBE_LOG:-$S/report.md}
W=$(mktemp -d)
mkdir -p "$S"; : >"$LOG"
REMOTE=${CLAUDE_CODE_REMOTE:-false}
PW_VER=1.63.0
MCR_IMAGE=mcr.microsoft.com/playwright:v$PW_VER-noble
SEMVER_VER=0.50.0
PORT=18765
say() { printf '%s\n' "$*" | tee -a "$LOG"; }
hdr() { say ""; say "### $1"; say ""; }
ms() { local n; n=$(date +%s%N); echo $(( n / 1000000 )); }
# row <name> <cmd...>: one table row with rc, ms and the output tail. T sets the timeout.
row() {
  local name=$1; shift; local t0 t1 rc out
  t0=$(ms); out=$(timeout "${T:-300}" "$@" 2>&1); rc=$?; t1=$(ms)
  out=$(tail -c 400 <<<"$out" | iconv -f utf-8 -t utf-8 -c | sed 's/\x1b\[[0-9;]*m//g' | tr '\n' ' ' | sed 's/|/\\|/g')
  say "| $name | $rc | $((t1-t0)) | \`$*\` | $out |"
}
thead() { say "| check | rc | ms | command | output tail |"; say "|---|---|---|---|---|"; }
# reach <url>: status of a 1-byte GET, redirect count and final host.
reach() { curl -sS -o /dev/null -r 0-0 -m 30 -L -w '%{http_code} | %{num_redirects} | %{url_effective}' "$1" 2>&1 | sed -E 's#(https?://[^/ ]+)[^ ]*$#\1#'; }
ver() { command -v "$1" >/dev/null 2>&1 && { shift; "$@" 2>&1 | head -1; } || echo "not installed"; }

say "## browser-route probe: $( [ "$REMOTE" = true ] && echo cloud || echo local control ) $(date -u +%FT%TZ)"

hdr "0. Session identity and machine"
say "- user: $(id -un) uid=$(id -u) home=$HOME cwd=$(pwd)"
say "- branch: $(git branch --show-current 2>&1) head=$(git rev-parse --short HEAD 2>&1)"
say "- CLAUDE_CODE_REMOTE=$REMOTE; proxy vars: $(env | grep -ciE '^(https?|no)_proxy=')"
say "- nproc: $(nproc); mem: $(free -g | awk '/Mem/{print $2" GB"}'); disk free on /tmp: $(df -h /tmp | awk 'NR==2{print $4}'); on /var/lib/docker: $(df -h /var/lib 2>/dev/null | awk 'NR==2{print $4}')"
say "- node: $(ver node node --version); npm: $(ver npm npm --version); docker: $(ver docker docker --version)"
say "- cargo: $(ver cargo cargo --version); rustc: $(ver rustc rustc --version)"

hdr "1. Preinstalled browsers"
for b in google-chrome google-chrome-stable chrome chromium chromium-browser chromium-cli chromedriver firefox microsoft-edge msedge headless_shell; do
  p=$(command -v "$b" 2>/dev/null) && say "- \`$b\`: $p -> $(readlink -f "$p") ($("$p" --version 2>&1 | head -1))" || say "- \`$b\`: not on PATH"
done
for d in "$HOME/.cache/ms-playwright" /ms-playwright /opt/google /opt/chromium /usr/lib/chromium /opt/microsoft; do
  [ -e "$d" ] && say "- dir \`$d\`: $(ls "$d" 2>&1 | tr '\n' ' ')" || say "- dir \`$d\`: absent"
done
say "- dpkg browser packages: $(dpkg -l 2>/dev/null | awk '/^ii/{print $2" "$3}' | grep -iE 'chrom|firefox|edge|playwright' | tr '\n' ';' )"
say "- global npm packages: $(npm ls -g --depth=0 2>/dev/null | tail -n +2 | tr '\n' ' ')"
say "- chrome-like binaries under /usr /opt /root (maxdepth 6): $(find /usr /opt "$HOME" -maxdepth 6 -type f \( -name chrome -o -name chromium -o -name headless_shell -o -name 'chrome-headless-shell' -o -name firefox \) 2>/dev/null | head -10 | tr '\n' ' ')"

hdr "2. Browser hosts (status of a 1-byte GET followed through redirects; 403 from the proxy = blocked)"
say "| host | status | redirects | final host | url |"; say "|---|---|---|---|---|"
while read -r name url; do say "| $name | $(reach "$url") | $url |"; done <<EOF
mcr-registry https://mcr.microsoft.com/v2/
mcr-tags https://mcr.microsoft.com/v2/playwright/tags/list
cdn-playwright-chromium https://cdn.playwright.dev/builds/cft/153.0.8010.12/linux64/chrome-headless-shell-linux64.zip
cdn-playwright-ffmpeg https://cdn.playwright.dev/dbazure/download/playwright/builds/ffmpeg/1011/ffmpeg-linux.zip
gcs-cft-direct https://storage.googleapis.com/chrome-for-testing-public/153.0.8010.12/linux64/chrome-headless-shell-linux64.zip
prss-ffmpeg-direct https://playwright.download.prss.microsoft.com/dbazure/download/playwright/builds/ffmpeg/1011/ffmpeg-linux.zip
packages-microsoft-edge https://packages.microsoft.com/repos/edge/dists/stable/Release
dl-google-chrome-deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
dl-google-apt https://dl.google.com/linux/chrome/deb/dists/stable/Release
EOF

hdr "3. MCR blob route without a daemon (index, amd64 manifest, first layer)"
acc='application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json'
idx=$(curl -sS -m 30 -H "Accept: $acc" "https://mcr.microsoft.com/v2/playwright/manifests/v$PW_VER-noble")
dg=$(python3 -c 'import sys,json;d=json.load(sys.stdin);m=d.get("manifests");print(next(x["digest"] for x in m if x.get("platform",{}).get("architecture")=="amd64") if m else "")' <<<"$idx" 2>/dev/null)
if [ -n "$dg" ]; then man=$(curl -sS -m 30 -H "Accept: $acc" "https://mcr.microsoft.com/v2/playwright/manifests/$dg"); else man=$idx; fi
layer=$(python3 -c 'import sys,json;print(json.load(sys.stdin)["layers"][0]["digest"])' <<<"$man" 2>/dev/null)
if [ -n "$layer" ]; then
  loc=$(curl -sS -m 30 -o /dev/null -w '%{redirect_url}' "https://mcr.microsoft.com/v2/playwright/blobs/$layer" | sed -E 's#^https?://([^/]+).*#\1#')
  fin=$(reach "https://mcr.microsoft.com/v2/playwright/blobs/$layer")
  say "- manifest ok; layer redirect host: ${loc:-none}; final: $fin"
else
  say "- manifest fetch failed: $(head -c 200 <<<"$idx$man" | tr '\n|' '  ')"
fi

hdr "4. MCR image pull and browser copy"
if ! docker info >/dev/null 2>&1 && [ "$REMOTE" = true ] && command -v dockerd >/dev/null 2>&1; then
  t0=$(ms); (dockerd >"$S/dockerd.log" 2>&1 &)
  for _ in $(seq 60); do docker info >/dev/null 2>&1 && break; sleep 1; done
  say "- dockerd start: $(( $(ms) - t0 )) ms, answering: $(docker info --format '{{.ServerVersion}}' 2>&1)"
fi
PWB=$S/ms-playwright
if docker info >/dev/null 2>&1; then
  thead
  docker image rm -f "$MCR_IMAGE" >/dev/null 2>&1
  T=900 row pull-mcr-cold docker pull -q "$MCR_IMAGE"
  row image-size docker image inspect -f '{{.Size}}' "$MCR_IMAGE"
  rm -rf "$PWB"
  row cp-ms-playwright bash -c "c=\$(docker create $MCR_IMAGE) && docker cp \$c:/ms-playwright '$PWB' && docker rm \$c >/dev/null && ls '$PWB' && du -sh '$PWB'"
else
  say "- no daemon: pull skipped"
fi

hdr "5. Driving headless Chromium from the copied browsers"
mkdir -p "$W/site" && printf '<title>probe-ok</title><button onclick="document.title=%s">go</button>\n' "'clicked'" >"$W/site/index.html"
(cd "$W/site" && python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 &)
sleep 1
cd "$W" || exit 1
thead
row npm-playwright bash -c "npm init -y >/dev/null && npm i -s playwright@$PW_VER"
if [ -d "$PWB" ]; then
  row lib-launch env PLAYWRIGHT_BROWSERS_PATH="$PWB" node -e "const {chromium}=require('playwright');(async()=>{const b=await chromium.launch();const p=await b.newPage();await p.goto('http://127.0.0.1:$PORT/');console.log(await p.title(), b.version());await b.close()})().catch(e=>{console.error(e.message);process.exit(1)})"
  row cli-open env PLAYWRIGHT_BROWSERS_PATH="$PWB" npx playwright cli open --browser=chromium "http://127.0.0.1:$PORT/"
  row cli-snapshot env PLAYWRIGHT_BROWSERS_PATH="$PWB" npx playwright cli snapshot
  row cli-click env PLAYWRIGHT_BROWSERS_PATH="$PWB" npx playwright cli click e2
  row cli-eval env PLAYWRIGHT_BROWSERS_PATH="$PWB" npx playwright cli eval "document.title"
  row cli-close env PLAYWRIGHT_BROWSERS_PATH="$PWB" npx playwright cli close
else
  say "| copied browsers | - | - | none (section 4 skipped or failed) | - |"
fi
# The vendor install route, into its own path so it cannot reuse the copy.
if [ "$REMOTE" = true ]; then DEPS=--with-deps; else DEPS=; fi
T=600 row pw-install-shell env PLAYWRIGHT_BROWSERS_PATH="$W/pw-install" npx playwright install $DEPS --only-shell chromium
row pw-install-launch env PLAYWRIGHT_BROWSERS_PATH="$W/pw-install" node -e "require('playwright').chromium.launch().then(b=>{console.log(b.version());return b.close()}).catch(e=>{console.error(e.message.split('\n')[0]);process.exit(1)})"

hdr "6. Container to the VM's localhost"
if docker info >/dev/null 2>&1; then
  thead
  row pull-alpine docker pull -q alpine:3.22
  row host-network docker run --rm --network host alpine:3.22 wget -qO- -T 5 "http://127.0.0.1:$PORT/"
  row bridge-host-gateway docker run --rm --add-host=host.docker.internal:host-gateway alpine:3.22 wget -qO- -T 5 "http://host.docker.internal:$PORT/"
  row mcr-image-host-network docker run --rm --network host "$MCR_IMAGE" bash -c "ls /ms-playwright && curl -s -m 5 http://127.0.0.1:$PORT/ || wget -qO- -T 5 http://127.0.0.1:$PORT/"
else
  say "- no daemon: skipped"
fi

hdr "7. cargo-semver-checks install"
if [ "${PROBE_SKIP_CARGO:-0}" = 1 ]; then
  say "- skipped (PROBE_SKIP_CARGO=1)"
elif command -v cargo >/dev/null 2>&1; then
  thead
  T=1500 row cargo-install env CARGO_TARGET_DIR="$W/target" cargo install --locked --root "$W/cargo" "cargo-semver-checks@$SEMVER_VER"
  row semver-checks-version "$W/cargo/bin/cargo-semver-checks" semver-checks --version
else
  say "- no cargo on PATH"
fi

pkill -f "http.server $PORT" 2>/dev/null
cd / && rm -rf "$W"
say ""; say "_end of probe_"

#!/usr/bin/env bash
# Local emulation of "is a Custom allowlist of cdn.playwright.dev alone enough"
# (#359). Runs `playwright install --only-shell chromium` through
# allowlist-proxy.py twice: blocking every Playwright host the Default cloud run
# refused (control: must fail like the cloud), then the same set minus
# cdn.playwright.dev (the Custom allowlist). storage.googleapis.com passed on
# Default, so neither run blocks it.
set -u
D=$(cd "$(dirname "$0")" && pwd); W=$(mktemp -d); cd "$W" || exit 1
npm init -y >/dev/null && npm i -s playwright@1.63.0 >/dev/null 2>&1
BASE=playwright.download.prss.microsoft.com,playwright.azureedge.net,playwright-akamai.azureedge.net,playwright-verizon.azureedge.net,dl.google.com
run() { # run <label> <block-list>
  BLOCK=$2 PORT=18888 python3 "$D/allowlist-proxy.py" 2>"$W/$1.proxy" & local p=$!; sleep 0.5
  local t0; t0=$(date +%s%N)
  HTTPS_PROXY=http://127.0.0.1:18888 PLAYWRIGHT_BROWSERS_PATH="$W/$1" npx playwright install --only-shell chromium >"$W/$1.out" 2>&1
  echo "### $1: rc=$? ms=$(( ($(date +%s%N)-t0)/1000000 ))"
  kill $p; echo '```'; sort "$W/$1.proxy" | uniq -c; grep -aE 'downloaded to|Error|Failed|fallback|Retrying' "$W/$1.out" | tail -6; ls "$W/$1" 2>&1; echo '```'
}
run default-blocked "$BASE,cdn.playwright.dev"
run custom-cdn-allowed "$BASE"
cd / && rm -rf "$W"

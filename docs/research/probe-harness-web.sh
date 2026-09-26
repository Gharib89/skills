#!/usr/bin/env bash
# Probe for "Web-session probe of cloud setup unknowns" (#342). Run once locally
# as the control, then in a Claude Code on the web session started on branch
# research/harness-web-probe. Prints a Markdown report to stdout and to
# $PROBE_LOG. Item numbers match the ticket's Question.
# Read-only against the repo and tracker; network writes are downloads into a
# scratch dir, removed at the end. System installs (apt, playwright deps) run
# only when CLAUDE_CODE_REMOTE=true.
set -u
LOG=${PROBE_LOG:-/tmp/harness-probe/report.md}
S=/tmp/harness-probe
W=$(mktemp -d)
mkdir -p "$S"; : >"$LOG"
REMOTE=${CLAUDE_CODE_REMOTE:-false}
say() { printf '%s\n' "$*" | tee -a "$LOG"; }
hdr() { say ""; say "### $1"; say ""; }
ms() { local n; n=$(date +%s%N); echo $(( n / 1000000 )); }
# row <name> <cmd...>: one table row with rc, ms and the output tail.
row() {
  local name=$1; shift; local t0 t1 rc out
  t0=$(ms); out=$(timeout 300 "$@" 2>&1); rc=$?; t1=$(ms)
  out=$(tail -c 300 <<<"$out" | tr '\n' ' ' | sed 's/|/\\|/g')
  say "| $name | $rc | $((t1-t0)) | \`$*\` | $out |"
}
thead() { say "| check | rc | ms | command | output tail |"; say "|---|---|---|---|---|"; }
# code <url>: HTTP status of a GET (first byte only).
code() { curl -sS -o /dev/null -r 0-0 -m 30 -w '%{http_code}' "$1" 2>&1; }

say "## harness web probe: $( [ "$REMOTE" = true ] && echo cloud || echo local control ) $(date -u +%FT%TZ)"

hdr "0. Session identity"
say "- user: $(id -un) uid=$(id -u) home=$HOME cwd=$(pwd)"
say "- branch: $(git branch --show-current 2>&1) head=$(git rev-parse --short HEAD 2>&1)"
say "- hostname: $(hostname) boot_id: $(cat /proc/sys/kernel/random/boot_id) up since: $(uptime -s 2>/dev/null)"
say "- CLAUDE_CODE_REMOTE=$REMOTE; proxy vars: $(env | grep -ciE '^(https?|no)_proxy=')"
say "- claude: $(command -v claude || echo none) $(claude --version 2>/dev/null)"

hdr "1-2. Setup script log (written by the environment setup script, one line per run)"
if [ -f /var/tmp/harness-probe/setup.log ]; then
  say '```'; tee -a "$LOG" </var/tmp/harness-probe/setup.log; say '```'
  say "- setup runs recorded: $(grep -c '^run ' /var/tmp/harness-probe/setup.log)"
else say "- no /var/tmp/harness-probe/setup.log (setup script line not installed, or not run)"; fi
# First-run marker: survives in /tmp only while this container lives.
if [ -f "$S/first-run" ]; then say "- first probe run in this container: $(cat "$S/first-run")"
else echo "$(date -u +%FT%TZ) host=$(hostname) boot=$(cat /proc/sys/kernel/random/boot_id)" >"$S/first-run"; say "- first probe run in this container: now"; fi

hdr "3. Registries and CDNs (HTTP status of a GET; 403 from the proxy = blocked)"
say "| host | status | url |"; say "|---|---|---|"
while read -r name url; do say "| $name | $(code "$url") | $url |"; done <<'EOF'
npm https://registry.npmjs.org/prettier/latest
pypi-simple https://pypi.org/simple/ruff/
pypi-files https://files.pythonhosted.org/
crates-index https://index.crates.io/config.json
crates-static https://static.crates.io/crates/serde/serde-1.0.200.crate
go-proxy https://proxy.golang.org/golang.org/x/tools/gopls/@latest
go-sum https://sum.golang.org/lookup/golang.org/x/tools/gopls@v0.16.0
rubygems https://rubygems.org/api/v1/gems/rubocop.json
maven-central https://repo1.maven.org/maven2/
gradle-plugins https://plugins.gradle.org/m2/
nuget https://api.nuget.org/v3/index.json
packagist https://repo.packagist.org/packages.json
rustup https://static.rust-lang.org/dist/channel-rust-stable.toml.sha256
ubuntu-archive http://archive.ubuntu.com/ubuntu/dists/noble/Release
nodesource https://deb.nodesource.com/
llvm-apt https://apt.llvm.org/
gh-cli-apt https://cli.github.com/packages/githubcli-archive-keyring.gpg
docker-hub https://registry-1.docker.io/v2/
playwright-cdn https://cdn.playwright.dev/
playwright-msft https://playwright.download.prss.microsoft.com/
playwright-azureedge https://playwright.azureedge.net/
chrome-for-testing https://storage.googleapis.com/chrome-for-testing-public/
raw-githubusercontent https://raw.githubusercontent.com/astral-sh/ruff/main/README.md
gh-release-unattached https://github.com/koalaman/shellcheck/releases/download/v0.10.0/shellcheck-v0.10.0.linux.x86_64.tar.xz
gh-release-golangci https://github.com/golangci/golangci-lint/releases/download/v1.61.0/golangci-lint-1.61.0-linux-amd64.tar.gz
gh-codeload https://codeload.github.com/pre-commit/pre-commit-hooks/tar.gz/refs/tags/v4.6.0
EOF

hdr "3b. Real installs through each registry (into a scratch dir)"
thead
cd "$W" || exit 1
row "npm pack prettier" npm pack --silent prettier
row "pip download ruff" python3 -m pip download -q --no-deps -d "$W/pip" ruff
row "pip download prek" python3 -m pip download -q --no-deps -d "$W/pip" prek
row "uv tool run prek --version" uv tool run --from prek prek --version
row "npx lefthook version" npx -y lefthook@latest version
row "go mod download gopls" env GOPATH="$W/go" GOFLAGS=-modcacherw go mod download -json golang.org/x/tools/gopls@latest
row "gem fetch rubocop" gem fetch rubocop
row "cargo search ripgrep" cargo search --limit 1 ripgrep
if [ "$REMOTE" = true ]; then
  row "apt-get update" apt-get update -qq
  row "apt-get install shellcheck" apt-get install -y -qq shellcheck
fi
row "playwright install chromium" env PLAYWRIGHT_BROWSERS_PATH="$W/pw" npx -y playwright@latest install chromium
if [ "$REMOTE" = true ]; then
  row "playwright install-deps chromium" npx -y playwright@latest install-deps chromium
fi
cat >"$W/pw.mjs" <<'EOF'
import { chromium } from 'playwright';
const b = await chromium.launch(); const p = await b.newPage();
await p.setContent('<h1>ok</h1>'); console.log(await p.textContent('h1')); await b.close();
EOF
(cd "$W" && npm init -y >/dev/null 2>&1 && npm i -s playwright@latest >/dev/null 2>&1)
row "playwright launch headless" env PLAYWRIGHT_BROWSERS_PATH="$W/pw" node "$W/pw.mjs"
cd - >/dev/null || true

hdr "5. Plugins and LSP"
say "- ~/.claude/plugins: $(ls ~/.claude/plugins 2>&1 | tr '\n' ' ')"
say "- installed_plugins.json: $(tr -d '\n ' <~/.claude/plugins/installed_plugins.json 2>&1 | head -c 400)"
say "- claude plugin list:"; say '```'; claude plugin list 2>&1 | head -20 | tee -a "$LOG"; say '```'
say "- pyright on PATH: $(command -v pyright-langserver || echo none)"
say "- language server processes: $(pgrep -af 'langserver|pyright' | grep -v pgrep | head -3 | tr '\n' ';' || true)"

hdr "6. Committed hooks fired (markers written by .claude/settings.json on this branch)"
for f in sessionstart posttooluse stop; do
  say "- $f: $( [ -f "$S/$f.log" ] && tail -n 3 "$S/$f.log" | tr '\n' ';' || echo 'no marker')"
done

hdr "7. Clone of a public repo not attached to the session"
thead
row "git ls-remote ruff-pre-commit" git ls-remote --tags https://github.com/astral-sh/ruff-pre-commit v0.6.9
row "git clone pre-commit-hooks" git clone -q --depth 1 https://github.com/pre-commit/pre-commit-hooks "$W/pch"
mkdir -p "$W/hookrepo" && cd "$W/hookrepo" && git init -q && printf 'x \n' >a.txt && git add a.txt
cat >.pre-commit-config.yaml <<'EOF'
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: trailing-whitespace
EOF
row "prek run (remote hook repo, cold)" env PREK_HOME="$W/prek" uv tool run --from prek prek run --all-files
row "prek run (warm)" env PREK_HOME="$W/prek" uv tool run --from prek prek run --all-files
cd - >/dev/null || true

hdr "8. Node"
say "- node on PATH: $(command -v node) $(node --version 2>&1); npm $(npm --version 2>&1)"
say "- all node binaries: $(which -a node 2>/dev/null | tr '\n' ' ')"
say "- nvm/n installs: $(ls -d ~/.nvm/versions/node/* /usr/local/n/versions/node/* /opt/nodejs* 2>/dev/null | tr '\n' ' ')"
thead
row "lint-staged 17 under PATH node" npx -y lint-staged@17 --version

rm -rf "$W"
say ""; say "_end of report_"

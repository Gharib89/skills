#!/usr/bin/env bash
# Follow-up for "Web-session probe of browser routes" (#359), run in the same warm
# cloud session after probe-browser-routes.sh found /opt/pw-browsers: can a
# repo's playwright 1.63.0 use the preinstalled browsers, and does Chrome for
# Testing download straight from storage.googleapis.com. Writes only under /tmp/fu.
set -u
echo "## A. preinstalled Playwright"
env | grep -iE '^[A-Z_]*(PLAYWRIGHT|CHROM)[A-Z_]*=' ; echo "--"
ls /opt/pw-browsers; ls /opt/pw-browsers/*/ | head -20
command -v playwright; playwright --version 2>&1
playwright cli --help 2>&1 | head -2
readlink -f "$(command -v playwright)"
ls -la /opt/pw-browsers/chromium_headless_shell-1194/ 2>&1 | head
grep -rl pw-browsers /etc/environment /etc/profile.d /root/.bashrc 2>/dev/null
echo "## B. repo playwright 1.63.0 against the preinstalled browsers"
rm -rf /tmp/fu && mkdir /tmp/fu && cd /tmp/fu && npm init -y >/dev/null && npm i -s playwright@1.63.0 >/dev/null 2>&1 && echo npm-ok
L='const pw=require("playwright");const o=process.argv[1]?{executablePath:process.argv[1]}:{};pw.chromium.launch(o).then(async b=>{const p=await b.newPage();await p.setContent("<title>ok</title><button>go</button>");await p.click("button");console.log("PASS",b.version(),await p.title());await b.close()}).catch(e=>{console.log("FAIL",e.message.split("\n")[0]);process.exit(1)})'
echo "- default path:"; node -e "$L"
echo "- PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers:"; PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers node -e "$L"
echo "- executablePath headless_shell-1194:"; node -e "$L" /opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell
echo "- executablePath chromium-1194:"; node -e "$L" /opt/pw-browsers/chromium-1194/chrome-linux/chrome
echo "## C. Chrome for Testing straight from storage.googleapis.com"
t0=$(date +%s%N)
curl -sS -o /tmp/fu/hs.zip https://storage.googleapis.com/chrome-for-testing-public/153.0.8010.12/linux64/chrome-headless-shell-linux64.zip && echo "download rc=$? bytes=$(stat -c %s /tmp/fu/hs.zip) ms=$(( ($(date +%s%N)-t0)/1000000 ))"
python3 -c 'import zipfile;zipfile.ZipFile("/tmp/fu/hs.zip").extractall("/tmp/fu/hs")' && chmod +x /tmp/fu/hs/chrome-headless-shell-linux64/chrome-headless-shell && echo unzip-ok
echo "- executablePath CfT 153:"; node -e "$L" /tmp/fu/hs/chrome-headless-shell-linux64/chrome-headless-shell
echo "- total ms=$(( ($(date +%s%N)-t0)/1000000 ))"
echo "_end of follow-up_"

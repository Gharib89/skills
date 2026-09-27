Local control on the dev machine (12 cores, Chrome and Playwright browsers preinstalled), run before the cloud session. Cargo section skipped: #353 measured the install at 286 s here. The `cli-click` row used the button text, which `playwright cli` rejects; the script now clicks the snapshot ref `e2`, re-checked by hand (title becomes `clicked`). ANSI codes and a split UTF-8 progress bar were stripped.

## browser-route probe: local control 2026-09-27T19:19:08Z

### 0. Session identity and machine

- user: ribo uid=1000 home=/home/ribo cwd=/home/ribo/wip/projects/skills/.claude/worktrees/browser-routes
- branch: research/harness-browser-routes head=93bfa43
- CLAUDE_CODE_REMOTE=false; proxy vars: 0
- nproc: 12; mem: 30 GB; disk free on /tmp: 14G; on /var/lib/docker: 317G
- node: v24.20.0; npm: 11.19.0; docker: Docker version 29.8.1, build 4a63305
- cargo: cargo 1.98.0 (797e8a9bc 2026-08-05); rustc: rustc 1.98.0 (88d9e12ae 2026-08-18)

### 1. Preinstalled browsers

- `google-chrome`: /usr/bin/google-chrome -> /opt/google/chrome/google-chrome (Google Chrome 154.0.8037.57 )
- `google-chrome-stable`: /usr/bin/google-chrome-stable -> /opt/google/chrome/google-chrome (Google Chrome 154.0.8037.57 )
- `chrome`: not on PATH
- `chromium`: /snap/bin/chromium -> /usr/bin/snap (update.go:193: cannot change mount namespace according to change mount (/var/lib/snapd/hostfs/usr/local/share/doc /usr/local/share/doc none bind,ro 0 0): cannot write to "/var/lib/snapd/hostfs/usr/local/share/doc" because it would affect the host in "/var/lib/snapd")
- `chromium-browser`: not on PATH
- `chromium-cli`: not on PATH
- `chromedriver`: not on PATH
- `firefox`: /usr/bin/firefox -> /usr/bin/firefox ()
- `microsoft-edge`: not on PATH
- `msedge`: not on PATH
- `headless_shell`: not on PATH
- dir `/home/ribo/.cache/ms-playwright`: b chromium-1243 chromium_headless_shell-1243 cli-update-check.json daemon ffmpeg-1011 
- dir `/ms-playwright`: absent
- dir `/opt/google`: chrome 
- dir `/opt/chromium`: absent
- dir `/usr/lib/chromium`: absent
- dir `/opt/microsoft`: absent
- dpkg browser packages: firefox 1:1snap1-0ubuntu9.1;google-chrome-stable 154.0.8037.57-1;libchromaprint1:amd64 1.6.0-2build1;
- global npm packages: ├── @aws/agentcore@0.30.0 ├── clawdbot@2026.1.24-3 ├── corepack@0.35.0 ├── gsd-pi@3.0.0 ├── mermaid-filter@1.4.7 └── npm@11.19.0  
- chrome-like binaries under /usr /opt /root (maxdepth 6): /usr/share/bash-completion/completions/firefox /usr/share/lintian/overrides/firefox /usr/bin/firefox /opt/google/chrome/chrome /home/ribo/.cache/puppeteer/chrome/linux-1108766/chrome-linux/chrome /home/ribo/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome /home/ribo/.cache/ms-playwright/chromium_headless_shell-1243/chrome-headless-shell-linux64/chrome-headless-shell 

### 2. Browser hosts (status of a 1-byte GET followed through redirects; 403 from the proxy = blocked)

| host | status | redirects | final host | url |
|---|---|---|---|---|
| mcr-registry | 200 | 0 | https://mcr.microsoft.com | https://mcr.microsoft.com/v2/ |
| mcr-tags | 206 | 0 | https://mcr.microsoft.com | https://mcr.microsoft.com/v2/playwright/tags/list |
| cdn-playwright-chromium | 206 | 1 | https://storage.googleapis.com | https://cdn.playwright.dev/builds/cft/153.0.8010.12/linux64/chrome-headless-shell-linux64.zip |
| cdn-playwright-ffmpeg | 206 | 1 | https://playwright.download.prss.microsoft.com | https://cdn.playwright.dev/dbazure/download/playwright/builds/ffmpeg/1011/ffmpeg-linux.zip |
| gcs-cft-direct | 206 | 0 | https://storage.googleapis.com | https://storage.googleapis.com/chrome-for-testing-public/153.0.8010.12/linux64/chrome-headless-shell-linux64.zip |
| prss-ffmpeg-direct | 206 | 0 | https://playwright.download.prss.microsoft.com | https://playwright.download.prss.microsoft.com/dbazure/download/playwright/builds/ffmpeg/1011/ffmpeg-linux.zip |
| packages-microsoft-edge | 206 | 0 | https://packages.microsoft.com | https://packages.microsoft.com/repos/edge/dists/stable/Release |
| dl-google-chrome-deb | 206 | 0 | https://dl.google.com | https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb |
| dl-google-apt | 206 | 0 | https://dl.google.com | https://dl.google.com/linux/chrome/deb/dists/stable/Release |

### 3. MCR blob route without a daemon (index, amd64 manifest, first layer)

- manifest ok; layer redirect host: westeurope.data.mcr.microsoft.com; final: 206 | 1 | https://westeurope.data.mcr.microsoft.com

### 4. MCR image pull and browser copy

| check | rc | ms | command | output tail |
|---|---|---|---|---|
| pull-mcr-cold | 0 | 141104 | `docker pull -q mcr.microsoft.com/playwright:v1.63.0-noble` | mcr.microsoft.com/playwright:v1.63.0-noble  |
| image-size | 0 | 106 | `docker image inspect -f {{.Size}} mcr.microsoft.com/playwright:v1.63.0-noble` | 3545220690  |
| cp-ms-playwright | 0 | 1808 | `bash -c c=$(docker create mcr.microsoft.com/playwright:v1.63.0-noble) && docker cp $c:/ms-playwright '/tmp/browser-probe/ms-playwright' && docker rm $c >/dev/null && ls '/tmp/browser-probe/ms-playwright' && du -sh '/tmp/browser-probe/ms-playwright'` | chromium-1243 chromium_headless_shell-1243 ffmpeg-1011 firefox-1543 webkit-2359 1.3G	/tmp/browser-probe/ms-playwright  |

### 5. Driving headless Chromium from the copied browsers

| check | rc | ms | command | output tail |
|---|---|---|---|---|
| npm-playwright | 0 | 1408 | `bash -c npm init -y >/dev/null && npm i -s playwright@1.63.0` |   |
| lib-launch | 0 | 507 | `env PLAYWRIGHT_BROWSERS_PATH=/tmp/browser-probe/ms-playwright node -e const {chromium}=require('playwright');(async()=>{const b=await chromium.launch();const p=await b.newPage();await p.goto('http://127.0.0.1:18765/');console.log(await p.title(), b.version());await b.close()})().catch(e=>{console.error(e.message);process.exit(1)})` | probe-ok 153.0.8010.12  |
| cli-open | 0 | 1408 | `env PLAYWRIGHT_BROWSERS_PATH=/tmp/browser-probe/ms-playwright npx playwright cli open --browser=chromium http://127.0.0.1:18765/` | ### Browser `default` opened with pid 222159. ### Ran Playwright code ```js await page.goto('http://127.0.0.1:18765/'); ``` ### Page - Page URL: http://127.0.0.1:18765/ - Page Title: probe-ok - Console: 1 errors, 0 warnings ### Snapshot - [Snapshot](.playwright-cli/page-2026-09-27T19-21-44-254Z.yml) ### Events - New console entries: .playwright-cli/console-2026-09-27T19-21-44-190Z.log#L1  |
| cli-snapshot | 0 | 807 | `env PLAYWRIGHT_BROWSERS_PATH=/tmp/browser-probe/ms-playwright npx playwright cli snapshot` | ### Page - Page URL: http://127.0.0.1:18765/ - Page Title: probe-ok - Console: 1 errors, 0 warnings ### Snapshot ```yaml - button "go" [ref=e2] ```  |
| cli-click | 1 | 808 | `env PLAYWRIGHT_BROWSERS_PATH=/tmp/browser-probe/ms-playwright npx playwright cli click go` | ### Error Error: "go" does not match any elements.  |
| cli-eval | 0 | 1308 | `env PLAYWRIGHT_BROWSERS_PATH=/tmp/browser-probe/ms-playwright npx playwright cli eval document.title` | ### Result "probe-ok" ### Ran Playwright code ```js await page.evaluate('() => (document.title)'); ```  |
| cli-close | 0 | 807 | `env PLAYWRIGHT_BROWSERS_PATH=/tmp/browser-probe/ms-playwright npx playwright cli close` | Browser 'default' closed  |
| pw-install-shell | 0 | 18920 | `env PLAYWRIGHT_BROWSERS_PATH=/tmp/tmp.bMLz33pxj5/pw-install npx playwright install --only-shell chromium` | ■■■■■■■■        \|  90% of 2.3 MiB \|■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■\| 100% of 2.3 MiB FFmpeg (playwright ffmpeg v1011) downloaded to /tmp/tmp.bMLz33pxj5/pw-install/ffmpeg-1011  |
| pw-install-launch | 0 | 407 | `env PLAYWRIGHT_BROWSERS_PATH=/tmp/tmp.bMLz33pxj5/pw-install node -e require('playwright').chromium.launch().then(b=>{console.log(b.version());return b.close()}).catch(e=>{console.error(e.message.split('\n')[0]);process.exit(1)})` | 153.0.8010.12  |

### 6. Container to the VM's localhost

| check | rc | ms | command | output tail |
|---|---|---|---|---|
| pull-alpine | 0 | 2809 | `docker pull -q alpine:3.22` | docker.io/library/alpine:3.22  |
| host-network | 0 | 307 | `docker run --rm --network host alpine:3.22 wget -qO- -T 5 http://127.0.0.1:18765/` | <title>probe-ok</title><button onclick="document.title='clicked'">go</button>  |
| bridge-host-gateway | 1 | 5311 | `docker run --rm --add-host=host.docker.internal:host-gateway alpine:3.22 wget -qO- -T 5 http://host.docker.internal:18765/` | wget: download timed out  |
| mcr-image-host-network | 0 | 307 | `docker run --rm --network host mcr.microsoft.com/playwright:v1.63.0-noble bash -c ls /ms-playwright && curl -s -m 5 http://127.0.0.1:18765/ || wget -qO- -T 5 http://127.0.0.1:18765/` | chromium-1243 chromium_headless_shell-1243 ffmpeg-1011 firefox-1543 webkit-2359 <title>probe-ok</title><button onclick="document.title='clicked'">go</button>  |

### 7. cargo-semver-checks install

- skipped (PROBE_SKIP_CARGO=1)

_end of probe_

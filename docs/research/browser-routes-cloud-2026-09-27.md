## browser-route probe: cloud 2026-09-27T19:23:43Z

Read from session `session_01Cfef6snE3kHvFnodCnAXdv` (environment `Default`, started with
`claude --cloud` on `research/harness-browser-routes` at 6c8f637). The page was read with
`=` and `&` masked and query strings stripped (the read tool blocks them as cookie data);
they are restored here. Everything else is verbatim.

### 0. Session identity and machine

- user: root uid=0 home=/root cwd=/home/user/repo
- branch: research/harness-browser-routes head=6c8f637
- CLAUDE_CODE_REMOTE=true; proxy vars: 4
- nproc: 4; mem: 15 GB; disk free on /tmp: 30G; on /var/lib/docker: 30G
- node: v22.22.2; npm: 10.9.7; docker: Docker version 29.3.1, build c2be9cc
- cargo: cargo 1.94.1 (29ea6fb6a 2026-03-24); rustc: rustc 1.94.1 (e408947bf 2026-03-25)

### 1. Preinstalled browsers

- `google-chrome`: not on PATH
- `google-chrome-stable`: not on PATH
- `chrome`: not on PATH
- `chromium`: not on PATH
- `chromium-browser`: not on PATH
- `chromium-cli`: not on PATH
- `chromedriver`: /opt/node22/bin/chromedriver -> /opt/node22/lib/node_modules/chromedriver/bin/chromedriver (ChromeDriver 147.0.7727.24 (09d377d9438dc95267369f74a073acd81bdde38f-refs/branch-heads/7727@{#1413}))
- `firefox`: not on PATH
- `microsoft-edge`: not on PATH
- `msedge`: not on PATH
- `headless_shell`: not on PATH
- dir `/root/.cache/ms-playwright`: absent
- dir `/ms-playwright`: absent
- dir `/opt/google`: absent
- dir `/opt/chromium`: absent
- dir `/usr/lib/chromium`: absent
- dir `/opt/microsoft`: absent
- dpkg browser packages: 
- global npm packages: +-- @anthropic-ai/claude-code@2.1.42 +-- chromedriver@147.0.0 +-- corepack@0.34.6 +-- eslint@10.1.0 +-- http-server@14.1.1 +-- nodemon@3.1.14 +-- npm@10.9.7 +-- playwright@1.56.1 +-- pnpm@10.33.0 +-- prettier@3.8.1 +-- serve@14.2.6 +-- ts-node@10.9.2 +-- typescript@6.0.2 `-- yarn@1.22.22  
- chrome-like binaries under /usr /opt /root (maxdepth 6): /opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell /opt/pw-browsers/chromium-1194/chrome-linux/chrome 

### 2. Browser hosts (status of a 1-byte GET followed through redirects; 403 from the proxy = blocked)

| host | status | redirects | final host | url |
|---|---|---|---|---|
| mcr-registry | 200 | 0 | https://mcr.microsoft.com | https://mcr.microsoft.com/v2/ |
| mcr-tags | 206 | 0 | https://mcr.microsoft.com | https://mcr.microsoft.com/v2/playwright/tags/list |
| cdn-playwright-chromium | curl: (56) CONNECT tunnel failed, response 403 000 | 0 | https://cdn.playwright.dev | https://cdn.playwright.dev/builds/cft/153.0.8010.12/linux64/chrome-headless-shell-linux64.zip |
| cdn-playwright-ffmpeg | curl: (56) CONNECT tunnel failed, response 403 000 | 0 | https://cdn.playwright.dev | https://cdn.playwright.dev/dbazure/download/playwright/builds/ffmpeg/1011/ffmpeg-linux.zip |
| gcs-cft-direct | 206 | 0 | https://storage.googleapis.com | https://storage.googleapis.com/chrome-for-testing-public/153.0.8010.12/linux64/chrome-headless-shell-linux64.zip |
| prss-ffmpeg-direct | curl: (56) CONNECT tunnel failed, response 403 000 | 0 | https://playwright.download.prss.microsoft.com | https://playwright.download.prss.microsoft.com/dbazure/download/playwright/builds/ffmpeg/1011/ffmpeg-linux.zip |
| packages-microsoft-edge | 206 | 0 | https://packages.microsoft.com | https://packages.microsoft.com/repos/edge/dists/stable/Release |
| dl-google-chrome-deb | curl: (56) CONNECT tunnel failed, response 403 000 | 0 | https://dl.google.com | https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb |
| dl-google-apt | curl: (56) CONNECT tunnel failed, response 403 000 | 0 | https://dl.google.com | https://dl.google.com/linux/chrome/deb/dists/stable/Release |

### 3. MCR blob route without a daemon (index, amd64 manifest, first layer)

- manifest ok; layer redirect host: eastus.data.mcr.microsoft.com; final: 206 | 1 | https://eastus.data.mcr.microsoft.com

### 4. MCR image pull and browser copy

- dockerd start: 4798 ms, answering: 29.3.1

| check | rc | ms | command | output tail |
|---|---|---|---|---|
| pull-mcr-cold | 0 | 50216 | `docker pull -q mcr.microsoft.com/playwright:v1.63.0-noble` | mcr.microsoft.com/playwright:v1.63.0-noble  |
| image-size | 0 | 60 | `docker image inspect -f {{.Size}} mcr.microsoft.com/playwright:v1.63.0-noble` | 955799827  |
| cp-ms-playwright | 0 | 14422 | `bash -c c=$(docker create mcr.microsoft.com/playwright:v1.63.0-noble) && docker cp $c:/ms-playwright '/tmp/browser-probe/ms-playwright' && docker rm $c >/dev/null && ls '/tmp/browser-probe/ms-playwright' && du -sh '/tmp/browser-probe/ms-playwright'` | chromium-1243 chromium_headless_shell-1243 ffmpeg-1011 firefox-1543 webkit-2359 1.3G	/tmp/browser-probe/ms-playwright  |

### 5. Driving headless Chromium from the copied browsers

| check | rc | ms | command | output tail |
|---|---|---|---|---|
| npm-playwright | 0 | 3667 | `bash -c npm init -y >/dev/null && npm i -s playwright@1.63.0` |   |
| lib-launch | 0 | 1604 | `env PLAYWRIGHT_BROWSERS_PATH=/tmp/browser-probe/ms-playwright node -e const {chromium}=require('playwright');(async()=>{const b=await chromium.launch();const p=await b.newPage();await p.goto('http://127.0.0.1:18765/');console.log(await p.title(), b.version());await b.close()})().catch(e=>{console.error(e.message);process.exit(1)})` | probe-ok 153.0.8010.12  |
| cli-open | 0 | 2939 | `env PLAYWRIGHT_BROWSERS_PATH=/tmp/browser-probe/ms-playwright npx playwright cli open --browser=chromium http://127.0.0.1:18765/` | ### Browser `default` opened with pid 1587. ### Ran Playwright code ```js await page.goto('http://127.0.0.1:18765/'); ``` ### Page - Page URL: http://127.0.0.1:18765/ - Page Title: probe-ok - Console: 1 errors, 0 warnings ### Snapshot - [Snapshot](.playwright-cli/page-2026-09-27T19-25-16-241Z.yml) ### Events - New console entries: .playwright-cli/console-2026-09-27T19-25-16-114Z.log#L1  |
| cli-snapshot | 0 | 1296 | `env PLAYWRIGHT_BROWSERS_PATH=/tmp/browser-probe/ms-playwright npx playwright cli snapshot` | ### Page - Page URL: http://127.0.0.1:18765/ - Page Title: probe-ok - Console: 1 errors, 0 warnings ### Snapshot ```yaml - button "go" [ref=e2] ```  |
| cli-click | 0 | 1685 | `env PLAYWRIGHT_BROWSERS_PATH=/tmp/browser-probe/ms-playwright npx playwright cli click e2` | ### Ran Playwright code ```js await page.getByRole('button', { name: 'go' }).click(); ``` ### Page - Page URL: http://127.0.0.1:18765/ - Page Title: clicked - Console: 1 errors, 0 warnings ### Snapshot - [Snapshot](.playwright-cli/page-2026-09-27T19-25-19-249Z.yml)  |
| cli-eval | 0 | 1755 | `env PLAYWRIGHT_BROWSERS_PATH=/tmp/browser-probe/ms-playwright npx playwright cli eval document.title` | ### Result "clicked" ### Ran Playwright code ```js await page.evaluate('() => (document.title)'); ```  |
| cli-close | 0 | 1454 | `env PLAYWRIGHT_BROWSERS_PATH=/tmp/browser-probe/ms-playwright npx playwright cli close` | Browser 'default' closed  |
| pw-install-shell | 1 | 15980 | `env PLAYWRIGHT_BROWSERS_PATH=/tmp/tmp.PrHVRMZbpE/pw-install npx playwright install --with-deps --only-shell chromium` | led to install browsers Error: Failed to download Chrome Headless Shell 153.0.8010.12 (playwright chromium-headless-shell v1243), caused by Error: Download failure, code=1     at ChildProcess.<anonymous> (/tmp/tmp.PrHVRMZbpE/node_modules/playwright-core/lib/coreBundle.js:32428:32)     at ChildProcess.emit (node:events:519:28)     at ChildProcess._handle.onexit (node:internal/child_process:293:12)  |
| pw-install-launch | 1 | 463 | `env PLAYWRIGHT_BROWSERS_PATH=/tmp/tmp.PrHVRMZbpE/pw-install node -e require('playwright').chromium.launch().then(b=>{console.log(b.version());return b.close()}).catch(e=>{console.error(e.message.split('\n')[0]);process.exit(1)})` | browserType.launch: Executable doesn't exist at /tmp/tmp.PrHVRMZbpE/pw-install/chromium_headless_shell-1243/chrome-headless-shell-linux64/chrome-headless-shell  |

### 6. Container to the VM's localhost

| check | rc | ms | command | output tail |
|---|---|---|---|---|
| pull-alpine | 0 | 2155 | `docker pull -q alpine:3.22` | docker.io/library/alpine:3.22  |
| host-network | 0 | 690 | `docker run --rm --network host alpine:3.22 wget -qO- -T 5 http://127.0.0.1:18765/` | <title>probe-ok</title><button onclick="document.title='clicked'">go</button>  |
| bridge-host-gateway | 1 | 386 | `docker run --rm --add-host=host.docker.internal:host-gateway alpine:3.22 wget -qO- -T 5 http://host.docker.internal:18765/` | wget: can't connect to remote host (172.17.0.1): Connection refused  |
| mcr-image-host-network | 0 | 228 | `docker run --rm --network host mcr.microsoft.com/playwright:v1.63.0-noble bash -c ls /ms-playwright && curl -s -m 5 http://127.0.0.1:18765/ \|\| wget -qO- -T 5 http://127.0.0.1:18765/` | chromium-1243 chromium_headless_shell-1243 ffmpeg-1011 firefox-1543 webkit-2359 <title>probe-ok</title><button onclick="document.title='clicked'">go</button>  |

### 7. cargo-semver-checks install

| check | rc | ms | command | output tail |
|---|---|---|---|---|
| cargo-install | 0 | 351205 | `env CARGO_TARGET_DIR=/tmp/tmp.PrHVRMZbpE/target cargo install --locked --root /tmp/tmp.PrHVRMZbpE/cargo cargo-semver-checks@0.50.0` | 15.0    Compiling urlencoding v2.1.3    Compiling cargo-semver-checks v0.50.0     Finished `release` profile [optimized] target(s) in 5m 51s   Installing /tmp/tmp.PrHVRMZbpE/cargo/bin/cargo-semver-checks    Installed package `cargo-semver-checks v0.50.0` (executable `cargo-semver-checks`) warning: be sure to add `/tmp/tmp.PrHVRMZbpE/cargo/bin` to your PATH to be able to run the installed binaries  |
| semver-checks-version | 0 | 7 | `/tmp/tmp.PrHVRMZbpE/cargo/bin/cargo-semver-checks semver-checks --version` | cargo-semver-checks 0.50.0  |

_end of probe_

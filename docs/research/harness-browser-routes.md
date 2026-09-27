# Web-session probe of browser routes (#359)

Measured 2026-09-27, launched from Claude Code 2.1.283 into cloud environment `Default`, with
[`probe-browser-routes.sh`](probe-browser-routes.sh) and [`probe-browser-followup.sh`](probe-browser-followup.sh)
on branch `research/harness-browser-routes`. Raw runs: [local control](browser-routes-control-2026-09-27.md),
[cloud run](browser-routes-cloud-2026-09-27.md), [cloud follow-up](browser-routes-followup-2026-09-27.md),
[Custom allowlist emulation](browser-routes-allowlist-emulation-2026-09-27.md). The cloud VM had
4 vCPUs, 15 GB RAM and 30 GB free disk; the local machine has 12 cores.

## Answers

1. **The cloud image ships a browser, not only `chromedriver`, and it sets
   `PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers` for every process.** A global
   `playwright@1.56.1` (`/opt/node22/bin/playwright`) comes with `/opt/pw-browsers/chromium-1194`,
   `chromium_headless_shell-1194` (both Chrome 141.0.7390.37) and `ffmpeg-1011`, all marked
   `INSTALLATION_COMPLETE`. `chromedriver` 147 is a global npm package with no matching Chrome.
   No Chrome, Chromium, Firefox, Edge or `chromium-cli` is on `PATH`, and no browser dpkg
   package is installed. The docs' Installed tools table (only `chromedriver`) is incomplete.
2. **A repo's own Playwright cannot use those browsers by default.** With `playwright@1.63.0`,
   `chromium.launch()` fails `Executable doesn't exist at /opt/pw-browsers/chromium_headless_shell-1243/...`:
   the image's variable points every Playwright at a directory holding only revision 1194.
   Passing `executablePath` to either 1194 binary launches, clicks and reads the title (Chrome
   141 under a 1.63 client, a pairing Playwright does not support: each release pins one
   revision). So the harness must set its own `PLAYWRIGHT_BROWSERS_PATH` (or install into
   `/opt/pw-browsers`) for any Playwright version other than 1.56.x; the preinstalled browser is
   usable only by a repo pinned to that version.
3. **The MCR route passes `Default` and fits the budget.** `mcr.microsoft.com` answers 200 and
   the layer blobs redirect to `eastus.data.mcr.microsoft.com` (206). dockerd start 4.8 s, cold
   `docker pull mcr.microsoft.com/playwright:v1.63.0-noble` 50.2 s, `docker create` plus
   `docker cp /ms-playwright` 14.4 s (1.3 GB: `chromium-1243`, `chromium_headless_shell-1243`,
   `ffmpeg-1011`, `firefox-1543`, `webkit-2359`). About 70 s of the 300 s cloud setup budget,
   against 141 s for the pull alone locally. With `PLAYWRIGHT_BROWSERS_PATH` on the copy, the
   library smoke (1.6 s) and `npx playwright cli` `open`, `snapshot`, `click e2`, `eval`, `close`
   all passed; the click changed the page title. The image tag equals the repo's `playwright`
   version, so it stays a browser pin.
4. **Chrome for Testing downloads straight from Google on `Default`.** `cdn.playwright.dev`
   (every path) and `playwright.download.prss.microsoft.com` are refused (`CONNECT tunnel failed,
   response 403`), but `storage.googleapis.com/chrome-for-testing-public/...` passes. It is the
   host `cdn.playwright.dev` 307-redirects Chromium downloads to (measured locally), so the bytes
   are the ones Playwright's installer would fetch. The 120 MB headless-shell zip downloaded in
   1.2 s in the cloud; unzip plus a 1.63.0 launch via `executablePath` passed, 5.5 s in all.
   Playwright's own installer cannot be pointed there (its paths are `builds/cft/<ver>/...`,
   Google's are `chrome-for-testing-public/<ver>/...`), so this route is a hand-placed binary:
   either `executablePath` in the repo's config or a written `chromium_headless_shell-<rev>/`
   layout with Playwright's marker files. Neither is a vendor-documented install.
5. **`packages.microsoft.com` passes, `dl.google.com` does not.** The Edge apt `Release` file
   answered 206; the Chrome `.deb` and the Chrome apt repo were refused. An Edge install through
   apt was not measured.
6. **A container reaches the VM's `localhost` only on host networking.** `docker run --network host`
   reached a server bound to `127.0.0.1` in 0.7 s, from both `alpine:3.22` and the MCR image.
   The default bridge with `--add-host=host.docker.internal:host-gateway` got `Connection refused`
   from 172.17.0.1, as a `127.0.0.1` bind implies. Containers still have no egress
   ([Web-session probe of container pulls](https://github.com/Gharib89/skills/issues/352), item 5).
7. **`cargo install --locked cargo-semver-checks@0.50.0` takes 351 s cold on the cloud VM**
   (Rust 1.94.1, `release` build 5 m 51 s), over the 300 s cloud setup budget on its own and
   slower than the 286 s measured locally on 12 cores. The installed binary answered `--version`.
8. **A Custom allowlist of `cdn.playwright.dev` alone is enough, measured by local emulation,
   not in a Custom cloud environment.** A CONNECT proxy ([`allowlist-proxy.py`](allowlist-proxy.py))
   refused the Playwright and Google hosts the `Default` run refused. Control, with
   `cdn.playwright.dev` also refused: `playwright install --only-shell chromium` failed with the
   cloud's error. With `cdn.playwright.dev` allowed it passed in 19.5 s: Chromium went
   `cdn.playwright.dev` to `storage.googleapis.com` (passes `Default`); ffmpeg's primary URL
   redirects to the refused `prss` host, its first fallback is that host, and its second fallback
   (`cdn.playwright.dev/builds/ffmpeg/...`) is served directly. This assumes the Custom environment
   keeps the default list, so `storage.googleapis.com` stays open.

## For the web UI kind's cloud route

Two routes need no human step on `Default`: the MCR copy (item 3, vendor image pinned by the
repo's Playwright version, about 70 s, needs dockerd started on the `SessionStart` path) and the
direct Chrome for Testing download (item 4, about 5 s, Google-hosted, but a hand-placed binary
rather than Playwright's installer). The vendor install stays the route behind a Custom allowlist
of `cdn.playwright.dev` (item 8). Whichever route is chosen, `cloud-setup.sh` must override the
image's `PLAYWRIGHT_BROWSERS_PATH` (item 2). `Local-only:` is not needed for the web UI kind.

cargo-semver-checks does not fit the cloud setup budget by install (item 7): it needs a
[Rung budgets](https://github.com/Gharib89/skills/issues/343) override with a reason, or a
`Local-only:` label for that tool.

## Unmeasured

- A real Custom cloud environment with `cdn.playwright.dev` added (item 8 is an emulation).
- How the harness's `PLAYWRIGHT_BROWSERS_PATH` reaches the agent's Bash tool in the cloud
  (a `SessionStart` hook's `CLAUDE_ENV_FILE` or a repo config), and whether the image's value
  is stable across image updates (its files are dated 31 March).
- Edge through `packages.microsoft.com` apt; Firefox or WebKit from the MCR copy.
- MCR pull time on a warm resume, and MCR throttling on shared egress.

## browser-route follow-up: cloud 2026-09-27

Second message in the same warm session (`session_01Cfef6snE3kHvFnodCnAXdv`, environment
`Default`), run after the main probe. Script: [`probe-browser-followup.sh`](probe-browser-followup.sh),
sent base64-encoded because the session checkout has no remote. `=` restored as in the
main report; everything else verbatim.

```
## A. preinstalled Playwright
PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers
--
chromium
chromium-1194
chromium_headless_shell-1194
ffmpeg-1011
/opt/pw-browsers/chromium-1194/:
DEPENDENCIES_VALIDATED
INSTALLATION_COMPLETE
chrome-linux
/opt/pw-browsers/chromium_headless_shell-1194/:
DEPENDENCIES_VALIDATED
INSTALLATION_COMPLETE
chrome-linux
/opt/pw-browsers/ffmpeg-1011/:
COPYING.LGPLv2.1
DEPENDENCIES_VALIDATED
INSTALLATION_COMPLETE
ffmpeg-linux
/opt/node22/bin/playwright
Version 1.56.1
Usage: npx playwright [options] [command]
/opt/node22/lib/node_modules/playwright/cli.js
total 12
drwxr-xr-x 3 root root 4096 Mar 31 13:31 .
drwxr-xr-x 6 root root 4096 Mar 31 13:31 ..
-rwxr-xr-x 1 root root    0 Mar 31 13:31 DEPENDENCIES_VALIDATED
-rwxr-xr-x 1 root root    0 Mar 31 13:31 INSTALLATION_COMPLETE
drwxr-xr-x 2 root root 4096 Mar 31 13:31 chrome-linux
## B. repo playwright 1.63.0 against the preinstalled browsers
npm-ok
- default path:
FAIL browserType.launch: Executable doesn't exist at /opt/pw-browsers/chromium_headless_shell-1243/chrome-headless-shell-linux64/chrome-headless-shell
- PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers:
FAIL browserType.launch: Executable doesn't exist at /opt/pw-browsers/chromium_headless_shell-1243/chrome-headless-shell-linux64/chrome-headless-shell
- executablePath headless_shell-1194:
PASS 141.0.7390.37 ok
- executablePath chromium-1194:
PASS 141.0.7390.37 ok
## C. Chrome for Testing straight from storage.googleapis.com
download rc=0 bytes=119809080 ms=1184
unzip-ok
- executablePath CfT 153:
PASS 153.0.8010.12 ok
- total ms=5503
_end of follow-up_
```

`playwright cli --help` printed the general usage (1.56.1 has no `cli` command). No file
under `/etc/environment`, `/etc/profile.d` or `/root/.bashrc` names `pw-browsers`, so the
variable comes from the image's process environment.

Local control of the same script (dev machine): sections A and B fail for want of
`/opt/pw-browsers`, the default path passes on the local cache, and section C downloads in
18.0 s and launches Chrome 153.0.8010.12.

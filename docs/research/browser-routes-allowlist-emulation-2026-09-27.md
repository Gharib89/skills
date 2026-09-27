## Custom allowlist emulation: local 2026-09-27

Output of [`probe-allowlist-emulation.sh`](probe-allowlist-emulation.sh) through [`allowlist-proxy.py`](allowlist-proxy.py) on the dev machine. Proxy log lines are counted per CONNECT target.

### default-blocked: rc=1 ms=2209
```
      5 403 cdn.playwright.dev:443
    at IncomingMessage.handleError (<tmp>/node_modules/playwright-core/lib/coreBundle.js:32551:23)
Error: Download failed: server returned code 403 body ''. URL: https://cdn.playwright.dev/builds/cft/153.0.8010.12/linux64/chrome-headless-shell-linux64.zip
    at IncomingMessage.handleError (<tmp>/node_modules/playwright-core/lib/coreBundle.js:32551:23)
Failed to install browsers
Error: Failed to download Chrome Headless Shell 153.0.8010.12 (playwright chromium-headless-shell v1243), caused by
Error: Download failure, code=1
```
### custom-cdn-allowed: rc=0 ms=19540
```
      2 403 playwright.download.prss.microsoft.com:443
      3 ok  cdn.playwright.dev:443
      1 ok  storage.googleapis.com:443
Chrome Headless Shell 153.0.8010.12 (playwright chromium-headless-shell v1243) downloaded to <tmp>/custom-cdn-allowed/chromium_headless_shell-1243
Error: Download failed: server returned code 403 body ''. URL: https://cdn.playwright.dev/dbazure/download/playwright/builds/ffmpeg/1011/ffmpeg-linux.zip
    at IncomingMessage.handleError (<tmp>/node_modules/playwright-core/lib/coreBundle.js:32551:23)
Error: Download failed: server returned code 403 body ''. URL: https://playwright.download.prss.microsoft.com/dbazure/download/playwright/builds/ffmpeg/1011/ffmpeg-linux.zip
    at IncomingMessage.handleError (<tmp>/node_modules/playwright-core/lib/coreBundle.js:32551:23)
FFmpeg (playwright ffmpeg v1011) downloaded to <tmp>/custom-cdn-allowed/ffmpeg-1011
chromium_headless_shell-1243
ffmpeg-1011
```

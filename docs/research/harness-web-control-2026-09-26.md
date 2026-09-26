## harness web probe: local control 2026-09-26T20:19:54Z

### 0. Session identity

- user: ribo uid=1000 home=/home/ribo cwd=/home/ribo/wip/projects/skills-research-web-probe
- branch: research/harness-web-probe head=93bfa43
- hostname: ribo boot_id: dd0d589b-070b-4ddc-a010-ebcae11536ff up since: 2026-09-26 10:02:38
- CLAUDE_CODE_REMOTE=false; proxy vars: 0
- claude: /home/ribo/.local/bin/claude 2.1.283 (Claude Code)

### 1-2. Setup script log (written by the environment setup script, one line per run)

- no /var/tmp/harness-probe/setup.log (setup script line not installed, or not run)
- first probe run in this container: now

### 3. Registries and CDNs (HTTP status of a GET; 403 from the proxy = blocked)

| host | status | url |
|---|---|---|
| npm | 200 | https://registry.npmjs.org/prettier/latest |
| pypi-simple | 206 | https://pypi.org/simple/ruff/ |
| pypi-files | 404 | https://files.pythonhosted.org/ |
| crates-index | 206 | https://index.crates.io/config.json |
| crates-static | 200 | https://static.crates.io/crates/serde/serde-1.0.200.crate |
| go-proxy | 206 | https://proxy.golang.org/golang.org/x/tools/gopls/@latest |
| go-sum | 206 | https://sum.golang.org/lookup/golang.org/x/tools/gopls@v0.16.0 |
| rubygems | 206 | https://rubygems.org/api/v1/gems/rubocop.json |
| maven-central | 206 | https://repo1.maven.org/maven2/ |
| gradle-plugins | 206 | https://plugins.gradle.org/m2/ |
| nuget | 206 | https://api.nuget.org/v3/index.json |
| packagist | 206 | https://repo.packagist.org/packages.json |
| rustup | 206 | https://static.rust-lang.org/dist/channel-rust-stable.toml.sha256 |
| ubuntu-archive | 206 | http://archive.ubuntu.com/ubuntu/dists/noble/Release |
| nodesource | 206 | https://deb.nodesource.com/ |
| llvm-apt | 206 | https://apt.llvm.org/ |
| gh-cli-apt | 206 | https://cli.github.com/packages/githubcli-archive-keyring.gpg |
| docker-hub | 401 | https://registry-1.docker.io/v2/ |
| playwright-cdn | 400 | https://cdn.playwright.dev/ |
| playwright-msft | 403 | https://playwright.download.prss.microsoft.com/ |
| playwright-azureedge | 307 | https://playwright.azureedge.net/ |
| chrome-for-testing | 403 | https://storage.googleapis.com/chrome-for-testing-public/ |
| raw-githubusercontent | 206 | https://raw.githubusercontent.com/astral-sh/ruff/main/README.md |
| gh-release-unattached | 302 | https://github.com/koalaman/shellcheck/releases/download/v0.10.0/shellcheck-v0.10.0.linux.x86_64.tar.xz |
| gh-release-golangci | 302 | https://github.com/golangci/golangci-lint/releases/download/v1.61.0/golangci-lint-1.61.0-linux-amd64.tar.gz |
| gh-codeload | 200 | https://codeload.github.com/pre-commit/pre-commit-hooks/tar.gz/refs/tags/v4.6.0 |

### 3b. Real installs through each registry (into a scratch dir)

| check | rc | ms | command | output tail |
|---|---|---|---|---|
| npm pack prettier | 0 | 1207 | `npm pack --silent prettier` | prettier-3.9.9.tgz  |
| pip download ruff | 1 | 107 | `python3 -m pip download -q --no-deps -d /tmp/tmp.KpHV4LWVXU/pip ruff` | /usr/bin/python3: No module named pip  |
| pip download prek | 1 | 106 | `python3 -m pip download -q --no-deps -d /tmp/tmp.KpHV4LWVXU/pip prek` | /usr/bin/python3: No module named pip  |
| uv tool run prek --version | 0 | 307 | `uv tool run --from prek prek --version` | Installed 1 package in 1ms prek 0.5.3  |
| npx lefthook version | 0 | 3008 | `npx -y lefthook@latest version` | 2.1.14  |
| go mod download gopls | 127 | 114 | `env GOPATH=/tmp/tmp.KpHV4LWVXU/go GOFLAGS=-modcacherw go mod download -json golang.org/x/tools/gopls@latest` | env: 'go': No such file or directory env: use -[v]S to pass options in shebang lines  |
| gem fetch rubocop | 127 | 5 | `gem fetch rubocop` | timeout: failed to execute process: No such file or directory (os error 2)  |
| cargo search ripgrep | 0 | 815 | `cargo search --limit 1 ripgrep` |     Updating crates.io index ripgrep = "15.2.0"    # ripgrep is a line-oriented search tool that recursively searches the current directory for a regex patter… ... and 679 crates more (use --limit N to see more) note: to learn more about a package, run `cargo info <name>`  |
| playwright install chromium | 0 | 47952 | `env PLAYWRIGHT_BROWSERS_PATH=/tmp/tmp.KpHV4LWVXU/pw npx -y playwright@latest install chromium` | ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■\| 100% of 114.3 MiB Chrome Headless Shell 153.0.8010.12 (playwright chromium-headless-shell v1243) downloaded to /tmp/tmp.KpHV4LWVXU/pw/chromium_headless_shell-1243  |
| playwright launch headless | 0 | 507 | `env PLAYWRIGHT_BROWSERS_PATH=/tmp/tmp.KpHV4LWVXU/pw node /tmp/tmp.KpHV4LWVXU/pw.mjs` | ok  |

### 5. Plugins and LSP

- ~/.claude/plugins: cache data installed_plugins.json installed_plugins.json.bak-20260905-173217 known_marketplaces.json known_marketplaces.json.bak-20260905-173217 marketplaces plugin-catalog-cache.json store synced 
- installed_plugins.json: {"version":2,"plugins":{"pyright-lsp@claude-plugins-official":[{"scope":"user","installPath":"/home/ribo/.claude/plugins/cache/claude-plugins-official/pyright-lsp/1.0.0","version":"1.0.0","installedAt":"2026-08-28T08:24:03.407Z","lastUpdated":"2026-08-28T08:24:03.407Z"}],"last30days@last30days-skill":[{"scope":"user","installPath":"/home/ribo/.claude/plugins/cache/last30days-skill/last30days/3.21.
- claude plugin list:
```
Installed plugins:

  ❯ claude-code-setup@claude-plugins-official
    Version: 1.0.0
    Scope: user
    Status: ✘ disabled

  ❯ code-modernization@claude-plugins-official
    Version: 1.0.0
    Scope: project
    Status: ✘ disabled

  ❯ eli5@claude-community
    Version: 1.0.0
    Scope: user
    Status: ✔ enabled

  ❯ frontend-design@claude-plugins-official
    Version: fa59bc903774
    Scope: user
```
- pyright on PATH: none
- language server processes: 

### 6. Committed hooks fired (markers written by .claude/settings.json on this branch)

- sessionstart: no marker
- posttooluse: no marker
- stop: no marker

### 7. Clone of a public repo not attached to the session

| check | rc | ms | command | output tail |
|---|---|---|---|---|
| git ls-remote ruff-pre-commit | 0 | 707 | `git ls-remote --tags https://github.com/astral-sh/ruff-pre-commit v0.6.9` | 75b98813cfb7e663870a28c74366a1e99d7bfe79	refs/tags/v0.6.9  |
| git clone pre-commit-hooks | 0 | 1008 | `git clone -q --depth 1 https://github.com/pre-commit/pre-commit-hooks /tmp/tmp.KpHV4LWVXU/pch` |   |
| prek run (remote hook repo, cold) | 1 | 2910 | `env PREK_HOME=/tmp/tmp.KpHV4LWVXU/prek uv tool run --from prek prek run --all-files` | trim trailing whitespace.................................................Failed - hook id: trailing-whitespace - description: trims trailing whitespace - exit code: 1 - files were modified by this hook    Fixing a.txt  |
| prek run (warm) | 0 | 107 | `env PREK_HOME=/tmp/tmp.KpHV4LWVXU/prek uv tool run --from prek prek run --all-files` | trim trailing whitespace.................................................Passed  |

### 8. Node

- node on PATH: /home/ribo/.nvm/versions/node/v24.20.0/bin/node v24.20.0; npm 11.19.0
- all node binaries: /home/ribo/.nvm/versions/node/v24.20.0/bin/node 
- nvm/n installs: /home/ribo/.nvm/versions/node/v24.20.0 
| check | rc | ms | command | output tail |
|---|---|---|---|---|
| lint-staged 17 under PATH node | 0 | 1908 | `npx -y lint-staged@17 --version` | 17.6.0  |

_end of report_

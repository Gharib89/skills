# Shell

## Signals
Kind: file kind
Extensions: .sh .bash
Shebangs: sh bash

## lint

### ShellCheck
Publisher: koalaman
Tier: 2: https://github.com/koalaman/shellcheck
Evidence: `.shellcheckrc`
Rung: edit
Run: `shellcheck {files}`
Hook: local
Pin: apt shellcheck
Route: `sudo apt-get install -y shellcheck`; Blocked: release binaries
Constraints: None.
Traps: the vendor hook, `koalaman/shellcheck-precommit`, is `language: docker_image`; this entry runs `local` instead since the cloud sandbox has no guaranteed Docker daemon. Results depend on cwd and `-P`/`source-path`.

## format

### shfmt
Publisher: mvdan
Tier: 2: https://github.com/mvdan/sh
Evidence: `.editorconfig`
Rung: edit
Run: `shfmt -w {files}`
Hook: local
Pin: package go mvdan.cc/sh/v3/cmd/shfmt
Route: `go install mvdan.cc/sh/v3/cmd/shfmt@{version}`; Blocked: None.
Constraints: None.
Traps: reads `.editorconfig`; apt's `shfmt` lags several releases behind, so a repo pinning a specific shfmt style should carry it in `.editorconfig`.

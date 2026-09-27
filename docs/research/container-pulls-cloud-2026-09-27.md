## container-pull probe: cloud 2026-09-27T14:01:37Z

Read from session `session_016iuXs1V1nEpBSW5pJPHHvs` (environment `Default`, started with
`claude --cloud` on `research/harness-container-pulls` at a230b46). Query strings in URLs and
ANSI colour codes were stripped when the page was read; `go: downloading` lines were
dropped from the crane-install tail. Everything else is verbatim.

### 0. Session identity and shipped versions

- user: root uid=0 home=/root cwd=/home/user/repo
- branch: research/harness-container-pulls head=a230b46
- CLAUDE_CODE_REMOTE=true; proxy vars: 4
- kernel: 6.18.44-fc-v42; cgroup: tmpfs; CapEff: 000001fffeffffff
- docker: Docker version 29.3.1, build c2be9cc
- dockerd: Docker version 29.3.1, build f78c987
- containerd: containerd containerd.io v2.2.2 301b2dac98f15c27117da5c8af12118a041a31d9
- buildx: github.com/docker/buildx v0.31.1 a2675950d46b2cb171b23c2015ca44fb88607531
- podman: not installed; skopeo: not installed; crane: not installed
- go: go version go1.24.7 linux/amd64
- docker.sock: ls: cannot access '/var/run/docker.sock': No such file or directory

### 1. Registry and blob hosts (HTTP status of a GET; 403 from the proxy = blocked)

| host | status | url |
|---|---|---|
| dockerhub-registry | 401 | https://registry-1.docker.io/v2/ |
| dockerhub-auth | 200 | https://auth.docker.io/token?... |
| dockerhub-cloudflare | 403 | https://production.cloudflare.docker.com/ |
| dockerhub-cloudfront | 403 | https://production.cloudfront.docker.com/ |
| ghcr-registry | 401 | https://ghcr.io/v2/ |
| ghcr-token | 200 | https://ghcr.io/token?... |
| ghcr-blobs | curl: (56) CONNECT tunnel failed, response 403 000 | https://pkg-containers.githubusercontent.com/ |

### 2. Blob fetch without a daemon (token, index, amd64 manifest, first layer)

| image | token | manifest | redirect host | final status | final host |
|---|---|---|---|---|---|
| hadolint/hadolint:v2.15.1 | ok | ok | production.cloudfront.docker.com | 206 | https://production.cloudfront.docker.com |
| koalaman/shellcheck:v0.11.0 | ok | ok | production.cloudfront.docker.com | 206 | https://production.cloudfront.docker.com |
| ghcr.io/hadolint/hadolint:v2.15.1 | ok | ok | pkg-containers.githubusercontent.com | curl: (56) CONNECT tunnel failed, response 403 000 | https://pkg-containers.githubusercontent.com |

### 3. dockerd

- dockerd started in 642 ms: 29.3.1 storage=overlayfs cgroup=cgroupfs

### 4. Pulls and runs through the daemon

| check | rc | ms | command | output tail |
|---|---|---|---|---|
| pull-dockerhub-hadolint | 0 | 2835 | `docker pull -q hadolint/hadolint:v2.15.1` | docker.io/hadolint/hadolint:v2.15.1 |
| pull-ghcr-hadolint | 0 | 1209 | `docker pull -q ghcr.io/hadolint/hadolint:v2.15.1` | ghcr.io/hadolint/hadolint:v2.15.1 |
| pull-dockerhub-shellcheck | 0 | 2264 | `docker pull -q koalaman/shellcheck:v0.11.0` | docker.io/koalaman/shellcheck:v0.11.0 |
| run-hadolint-warm | 1 | 493 | `docker run --rm -i hadolint/hadolint:v2.15.1 <Dockerfile` | -:2 DL3018 warning ... -:2 DL3019 info ... -:3 DL3025 warning ... |
| run-shellcheck-warm | 1 | 386 | `docker run --rm -v ...:/mnt:ro koalaman/shellcheck:v0.11.0 /mnt/x.sh` | In /mnt/x.sh line 2: echo $1 ^-- SC2086 (info) ... |
| build-check-cold | 1 | 1071 | `docker build --check <dir>` | WARNING: JSONArgsRecommended ... Dockerfile:3 |
| build-check-warm | 1 | 301 | `docker build --check <dir>` | WARNING: JSONArgsRecommended ... Dockerfile:3 |

The ghcr.io pull reused layers: the Docker Hub and ghcr.io images share one digest
(`sha256:32dac941...`, checked locally), so only the manifest came from ghcr.io. See the
follow-up below for a cold ghcr.io pull.

### 5. Routes that need no daemon

| check | rc | ms | command | output tail |
|---|---|---|---|---|
| crane-install | 0 | 23638 | `env GOBIN=... go install github.com/google/go-containerregistry/cmd/crane@v0.22.1` | (go: downloading ...) |
| crane-export-hadolint | 0 | 2396 | `crane export --platform linux/amd64 hadolint/hadolint:v2.15.1 - \| tar -xf - bin/hadolint && ./bin/hadolint --version` | Haskell Dockerfile Linter 2.15.1 |
| crane-hadolint-run | 1 | 23 | `./bin/hadolint Dockerfile` | DL3018, DL3019, DL3025 (same findings as the container run) |
| pip-hadolint-bin | 0 | 1160 | `python3 -m pip download -q --no-deps -d ... hadolint-bin` | |
| pip-hadolint-py | 0 | 708 | `python3 -m pip download -q --no-deps --only-binary=:all: -d ... hadolint-py` | |

_end of probe_

## Follow-up in the same session: cold pulls after `docker system prune -af`

Prompted as a second message; output verbatim except the signed blob URL's query string,
which the reply truncated to its tail (Azure SAS parameters, `sr=b`, `hmac=...`).

```
dockerd-proxy-vars: 4
0
ghcr.io/hadolint/hadolint:v2.15.1-debian rc=1 s=2 ...&sr=b&sv=2025-01-05&hmac=...": Forbidden
ghcr.io/hadolint/hadolint:v2.15.1 rc=1 s=1 ...&sr=b&sv=2025-01-05&hmac=...": Forbidden
koalaman/shellcheck:v0.11.0 rc=0 s=3 docker.io/koalaman/shellcheck:v0.11.0
alpine:3.22 rc=0 s=1 docker.io/library/alpine:3.22
container-egress-rc=1
```

`container-egress-rc=1` is `docker run --rm alpine:3.22 wget -q -O- -T 10 https://pypi.org/simple/`:
a container has no route out (the proxy variables reach dockerd, not the container).

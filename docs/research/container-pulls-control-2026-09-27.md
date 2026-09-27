## container-pull probe: local control 2026-09-27T13:59:50Z

### 0. Session identity and shipped versions

- user: ribo uid=1000 home=/home/ribo cwd=/home/ribo/wip/projects/skills-research-container-pulls
- branch: research/harness-container-pulls head=93bfa43
- CLAUDE_CODE_REMOTE=false; proxy vars: 0
- kernel: 7.0.0-34-generic; cgroup: cgroup2fs; CapEff: 0000000000000000
- docker: Docker version 29.8.1, build 4a63305
- dockerd: Docker version 29.8.1, build 464cd50
- containerd: containerd containerd v2.3.6 ee2735368117d2eb259779949d5e75cdafec9761
- buildx: github.com/docker/buildx v0.37.1 0b265a9f62db554fa9aba6dd19e1bd5704bc7d8a
- podman: not installed; skopeo: not installed; crane: not installed
- go: not installed
- docker.sock: srw-rw---- 1 root docker 0 Sep 27 13:58 /var/run/docker.sock

### 1. Registry and blob hosts (HTTP status of a GET; 403 from the proxy = blocked)

| host | status | url |
|---|---|---|
| dockerhub-registry | 401 | https://registry-1.docker.io/v2/ |
| dockerhub-auth | 200 | https://auth.docker.io/token?service=registry.docker.io&scope=repository:hadolint/hadolint:pull |
| dockerhub-cloudflare | 403 | https://production.cloudflare.docker.com/ |
| dockerhub-cloudfront | 403 | https://production.cloudfront.docker.com/ |
| ghcr-registry | 401 | https://ghcr.io/v2/ |
| ghcr-token | 200 | https://ghcr.io/token?scope=repository:hadolint/hadolint:pull |
| ghcr-blobs | 400 | https://pkg-containers.githubusercontent.com/ |

### 2. Blob fetch without a daemon (token, index, amd64 manifest, first layer)

Each row: the layer GET's first redirect Location host, then the final status and host after following it.

| image | token | manifest | redirect host | final status | final host |
|---|---|---|---|---|---|
| hadolint/hadolint:v2.15.1 | ok | ok | production.cloudfront.docker.com | 206 | https://production.cloudfront.docker.com |
| koalaman/shellcheck:v0.11.0 | ok | ok | production.cloudfront.docker.com | 206 | https://production.cloudfront.docker.com |
| ghcr.io/hadolint/hadolint:v2.15.1 | ok | ok | pkg-containers.githubusercontent.com | 206 | https://pkg-containers.githubusercontent.com |

### 3. dockerd

- daemon already running: 29.8.1 storage=overlayfs cgroup=systemd

### 4. Pulls and runs through the daemon

| check | rc | ms | command | output tail |
|---|---|---|---|---|
| pull-dockerhub-hadolint | 0 | 2909 | `docker pull -q hadolint/hadolint:v2.15.1` | docker.io/hadolint/hadolint:v2.15.1  |
| pull-ghcr-hadolint | 0 | 1607 | `docker pull -q ghcr.io/hadolint/hadolint:v2.15.1` | ghcr.io/hadolint/hadolint:v2.15.1  |
| pull-dockerhub-shellcheck | 0 | 3809 | `docker pull -q koalaman/shellcheck:v0.11.0` | docker.io/koalaman/shellcheck:v0.11.0  |
| run-hadolint-warm | 1 | 307 | `bash -c docker run --rm -i hadolint/hadolint:v2.15.1 <'/tmp/tmp.YGvwHthKhw/Dockerfile'` | -:2 DL3018 [1m[93mwarning[0m: Pin versions in apk add. Instead of `apk add <package>` use `apk add <package>=<version>` -:2 DL3019 [92minfo[0m: Use the `--no-cache` switch to avoid the need to use `--update` and remove `/var/cache/apk/*` when done installing packages -:3 DL3025 [1m[93mwarning[0m: Use arguments JSON notation for CMD and ENTRYPOINT arguments  |
| run-shellcheck-warm | 1 | 313 | `docker run --rm -v /tmp/tmp.YGvwHthKhw:/mnt:ro koalaman/shellcheck:v0.11.0 /mnt/x.sh` |  In /mnt/x.sh line 2: echo $1      ^-- SC2086 (info): Double quote to prevent globbing and word splitting.  Did you mean: echo "$1"  For more information:   https://www.shellcheck.net/wiki/SC2086 -- Double quote to prevent globbing ...  |
| build-check-cold | 1 | 4921 | `docker build --check /tmp/tmp.YGvwHthKhw` | \|     CMD echo hi --------------------  WARNING: JSONArgsRecommended - https://docs.docker.com/go/dockerfile/rule/json-args-recommended/ JSON arguments recommended for CMD to prevent unintended behavior related to OS signals /tmp/tmp.YGvwHthKhw/Dockerfile:3 --------------------    1 \|     from alpine:3.22 as build    2 \|     RUN apk add curl    3 \| >>> CMD echo hi    4 \|      --------------------  |
| build-check-warm | 1 | 406 | `docker build --check /tmp/tmp.YGvwHthKhw` | \|     CMD echo hi --------------------  WARNING: JSONArgsRecommended - https://docs.docker.com/go/dockerfile/rule/json-args-recommended/ JSON arguments recommended for CMD to prevent unintended behavior related to OS signals /tmp/tmp.YGvwHthKhw/Dockerfile:3 --------------------    1 \|     from alpine:3.22 as build    2 \|     RUN apk add curl    3 \| >>> CMD echo hi    4 \|      --------------------  |

### 5. Routes that need no daemon

| check | rc | ms | command | output tail |
|---|---|---|---|---|
| crane | - | - | no go on PATH | - |
| pip-hadolint-bin | 1 | 107 | `python3 -m pip download -q --no-deps -d /tmp/tmp.YGvwHthKhw/pip hadolint-bin` | /usr/bin/python3: No module named pip  |
| pip-hadolint-py | 1 | 113 | `python3 -m pip download -q --no-deps --only-binary=:all: -d /tmp/tmp.YGvwHthKhw/pip hadolint-py` | /usr/bin/python3: No module named pip  |

_end of probe_

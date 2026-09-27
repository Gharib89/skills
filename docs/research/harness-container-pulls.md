# Web-session probe of container pulls (#352)

Measured 2026-09-27 on Claude Code 2.1.283 in cloud environment `Default`, with
[`probe-container-pulls.sh`](probe-container-pulls.sh) on branch
`research/harness-container-pulls`. Raw runs: [local control](container-pulls-control-2026-09-27.md),
[cloud run and cold-pull follow-up](container-pulls-cloud-2026-09-27.md).

## Answers

1. **dockerd is shipped but not running; it starts on demand.** No `/var/run/docker.sock`
   at session start. The probe, running as root (`CapEff 000001fffeffffff`, cgroup `tmpfs`),
   started `dockerd` in the background and it answered in 642 ms (overlayfs storage,
   cgroupfs driver). The daemon inherits the session's four proxy variables. A process
   does not survive an idle restart (#342), so whatever starts dockerd must be the
   `SessionStart` path, not setup alone.
2. **Docker Hub pulls work.** `hadolint/hadolint:v2.15.1` (2.8 s), `koalaman/shellcheck:v0.11.0`
   (2.3 s cold, 3 s after a prune) and `alpine:3.22` pulled. Blobs redirect to
   `production.cloudfront.docker.com`, which the proxy passes (a daemonless `curl` of a
   hadolint layer got 206 from there). The allowlist's `production.cloudflare.docker.com`
   spelling does not matter: the real blob host passes. The 403 both hosts give at `/`
   is the CDN's own answer, seen locally too, not the proxy's.
3. **ghcr.io pulls fail.** Token and manifest pass (`ghcr.io` answers), but layer blobs
   redirect to `pkg-containers.githubusercontent.com`, where the proxy refuses the CONNECT
   (403). Cold `docker pull ghcr.io/hadolint/hadolint:v2.15.1` and `:v2.15.1-debian` both
   fail with `Forbidden` on the signed blob URL. The first run's ghcr.io "pass" was layer
   reuse: the two registries serve the same digest (`sha256:32dac941...`). A ghcr.io image
   needs `pkg-containers.githubusercontent.com` on a Custom allowlist.
4. **Linting runs.** `docker run --rm -i hadolint/hadolint:v2.15.1 < Dockerfile` reported
   DL3018, DL3019, DL3025 (0.5 s warm); the shellcheck image reported SC2086 (0.4 s warm);
   `docker build --check` reported JSONArgsRecommended (1.1 s cold, including the base
   image's metadata from Docker Hub, 0.3 s warm). `--check` resolves the `FROM` image, so a
   Dockerfile whose base lives on ghcr.io (or a private registry) fails that way too.
5. **Containers have no egress.** `docker run alpine wget https://pypi.org/simple/` failed:
   the proxy reaches dockerd, not the container. Offline linters are unaffected; a
   `RUN` that fetches during a real build would fail.
6. **Daemonless route exists.** `go install .../crane@v0.22.1` (24 s) then
   `crane export hadolint/hadolint:v2.15.1 - | tar -x bin/hadolint` produced a working
   hadolint 2.15.1 binary in 2.4 s with no daemon. The third-party PyPI wrappers
   `hadolint-bin` and `hadolint-py` also download (neither is the vendor's).
7. **Shipped versions:** Docker 29.3.1 (client c2be9cc, daemon f78c987), containerd
   2.2.2, Buildx 0.31.1, Go 1.24.7. No podman, skopeo or crane. Local control: Docker
   29.8.1, Buildx 0.37.1.

Not measured: Docker Hub's anonymous pull rate limit against the cloud's shared egress.

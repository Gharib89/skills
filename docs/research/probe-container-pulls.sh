#!/usr/bin/env bash
# Probe for "Web-session probe of container pulls" (#352). Run once locally as
# the control, then in a Claude Code on the web session started on branch
# research/harness-container-pulls. Prints a Markdown report to stdout and to
# $PROBE_LOG. Section numbers follow the ticket's Question.
# Read-only against the repo and tracker. Starting dockerd and apt installs run
# only when CLAUDE_CODE_REMOTE=true; locally the running daemon is used as is.
set -u
S=/tmp/container-probe
LOG=${PROBE_LOG:-$S/report.md}
W=$(mktemp -d)
mkdir -p "$S"; : >"$LOG"
REMOTE=${CLAUDE_CODE_REMOTE:-false}
HADOLINT_TAG=v2.15.1
SHELLCHECK_TAG=v0.11.0
CRANE_VER=v0.22.1
say() { printf '%s\n' "$*" | tee -a "$LOG"; }
hdr() { say ""; say "### $1"; say ""; }
ms() { local n; n=$(date +%s%N); echo $(( n / 1000000 )); }
# row <name> <cmd...>: one table row with rc, ms and the output tail.
row() {
  local name=$1; shift; local t0 t1 rc out
  t0=$(ms); out=$(timeout 300 "$@" 2>&1); rc=$?; t1=$(ms)
  out=$(tail -c 400 <<<"$out" | tr '\n' ' ' | sed 's/|/\\|/g')
  say "| $name | $rc | $((t1-t0)) | \`$*\` | $out |"
}
thead() { say "| check | rc | ms | command | output tail |"; say "|---|---|---|---|---|"; }
code() { curl -sS -o /dev/null -r 0-0 -m 30 -w '%{http_code}' "$1" 2>&1; }
ver() { command -v "$1" >/dev/null 2>&1 && { shift; "$@" 2>&1 | head -1; } || echo "not installed"; }

say "## container-pull probe: $( [ "$REMOTE" = true ] && echo cloud || echo local control ) $(date -u +%FT%TZ)"

hdr "0. Session identity and shipped versions"
say "- user: $(id -un) uid=$(id -u) home=$HOME cwd=$(pwd)"
say "- branch: $(git branch --show-current 2>&1) head=$(git rev-parse --short HEAD 2>&1)"
say "- CLAUDE_CODE_REMOTE=$REMOTE; proxy vars: $(env | grep -ciE '^(https?|no)_proxy=')"
say "- kernel: $(uname -r); cgroup: $(stat -fc %T /sys/fs/cgroup 2>&1); CapEff: $(grep CapEff /proc/self/status | awk '{print $2}')"
say "- docker: $(ver docker docker --version)"
say "- dockerd: $(ver dockerd dockerd --version)"
say "- containerd: $(ver containerd containerd --version)"
say "- buildx: $(ver docker docker buildx version)"
say "- podman: $(ver podman podman --version); skopeo: $(ver skopeo skopeo --version); crane: $(ver crane crane version)"
say "- go: $(ver go go version)"
say "- docker.sock: $(ls -l /var/run/docker.sock 2>&1)"

hdr "1. Registry and blob hosts (HTTP status of a GET; 403 from the proxy = blocked)"
say "| host | status | url |"; say "|---|---|---|"
while read -r name url; do say "| $name | $(code "$url") | $url |"; done <<'EOF'
dockerhub-registry https://registry-1.docker.io/v2/
dockerhub-auth https://auth.docker.io/token?service=registry.docker.io&scope=repository:hadolint/hadolint:pull
dockerhub-cloudflare https://production.cloudflare.docker.com/
dockerhub-cloudfront https://production.cloudfront.docker.com/
ghcr-registry https://ghcr.io/v2/
ghcr-token https://ghcr.io/token?scope=repository:hadolint/hadolint:pull
ghcr-blobs https://pkg-containers.githubusercontent.com/
EOF

hdr "2. Blob fetch without a daemon (token, index, amd64 manifest, first layer)"
say "Each row: the layer GET's first redirect Location host, then the final status and host after following it."
say ""
say "| image | token | manifest | redirect host | final status | final host |"; say "|---|---|---|---|---|---|"
# blob_route <label> <registry> <repo> <tag> <token-url>
blob_route() {
  local label=$1 reg=$2 repo=$3 tag=$4 turl=$5 tok idx dg man layer loc fin
  local acc='application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json'
  tok=$(curl -sS -m 30 "$turl" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("token") or d.get("access_token") or "")' 2>/dev/null)
  [ -n "$tok" ] || { say "| $label | fail | - | - | - | - |"; return; }
  idx=$(curl -sS -m 30 -H "Authorization: Bearer $tok" -H "Accept: $acc" "https://$reg/v2/$repo/manifests/$tag")
  dg=$(python3 -c 'import sys,json;d=json.load(sys.stdin);m=d.get("manifests");print(next(x["digest"] for x in m if x.get("platform",{}).get("architecture")=="amd64") if m else "")' <<<"$idx" 2>/dev/null)
  if [ -n "$dg" ]; then man=$(curl -sS -m 30 -H "Authorization: Bearer $tok" -H "Accept: $acc" "https://$reg/v2/$repo/manifests/$dg"); else man=$idx; fi
  layer=$(python3 -c 'import sys,json;print(json.load(sys.stdin)["layers"][0]["digest"])' <<<"$man" 2>/dev/null)
  [ -n "$layer" ] || { say "| $label | ok | fail: $(head -c 120 <<<"$man" | tr '\n|' '  ') | - | - | - |"; return; }
  loc=$(curl -sS -m 30 -o /dev/null -w '%{redirect_url}' -H "Authorization: Bearer $tok" "https://$reg/v2/$repo/blobs/$layer" | sed -E 's#^https?://([^/]+).*#\1#')
  fin=$(curl -sS -m 60 -o /dev/null -r 0-1023 -L -w '%{http_code} %{url_effective}' -H "Authorization: Bearer $tok" "https://$reg/v2/$repo/blobs/$layer" 2>&1 | sed -E 's#(https?://[^/ ]+)[^ ]*#\1#')
  say "| $label | ok | ok | ${loc:-none} | ${fin% *} | ${fin#* } |"
}
blob_route "hadolint/hadolint:$HADOLINT_TAG" registry-1.docker.io hadolint/hadolint "$HADOLINT_TAG" \
  "https://auth.docker.io/token?service=registry.docker.io&scope=repository:hadolint/hadolint:pull"
blob_route "koalaman/shellcheck:$SHELLCHECK_TAG" registry-1.docker.io koalaman/shellcheck "$SHELLCHECK_TAG" \
  "https://auth.docker.io/token?service=registry.docker.io&scope=repository:koalaman/shellcheck:pull"
blob_route "ghcr.io/hadolint/hadolint:$HADOLINT_TAG" ghcr.io hadolint/hadolint "$HADOLINT_TAG" \
  "https://ghcr.io/token?scope=repository:hadolint/hadolint:pull"

hdr "3. dockerd"
if docker info >/dev/null 2>&1; then
  say "- daemon already running: $(docker info --format '{{.ServerVersion}} storage={{.Driver}} cgroup={{.CgroupDriver}}' 2>&1)"
elif [ "$REMOTE" = true ]; then
  if ! command -v dockerd >/dev/null 2>&1; then
    thead
    row apt-docker bash -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io'
    say "- after apt: docker $(ver docker docker --version); buildx $(ver docker docker buildx version)"
  fi
  if command -v dockerd >/dev/null 2>&1; then
    t0=$(ms); (dockerd >"$S/dockerd.log" 2>&1 &)
    for _ in $(seq 60); do docker info >/dev/null 2>&1 && break; sleep 1; done
    if docker info >/dev/null 2>&1; then
      say "- dockerd started in $(( $(ms) - t0 )) ms: $(docker info --format '{{.ServerVersion}} storage={{.Driver}} cgroup={{.CgroupDriver}}' 2>&1)"
    else
      say "- dockerd did not answer within 60 s; log tail:"; say '```'; tail -20 "$S/dockerd.log" | tee -a "$LOG"; say '```'
    fi
  fi
else
  say "- no daemon locally and not remote: skipping start"
fi

hdr "4. Pulls and runs through the daemon"
printf 'from alpine:3.22 as build\nRUN apk add curl\nCMD echo hi\n' >"$W/Dockerfile"
printf '#!/bin/sh\necho $1\n' >"$W/x.sh"
if docker info >/dev/null 2>&1; then
  thead
  row pull-dockerhub-hadolint docker pull -q "hadolint/hadolint:$HADOLINT_TAG"
  row pull-ghcr-hadolint docker pull -q "ghcr.io/hadolint/hadolint:$HADOLINT_TAG"
  row pull-dockerhub-shellcheck docker pull -q "koalaman/shellcheck:$SHELLCHECK_TAG"
  row run-hadolint-warm bash -c "docker run --rm -i hadolint/hadolint:$HADOLINT_TAG <'$W/Dockerfile'"
  row run-shellcheck-warm docker run --rm -v "$W:/mnt:ro" "koalaman/shellcheck:$SHELLCHECK_TAG" /mnt/x.sh
  row build-check-cold docker build --check "$W"
  row build-check-warm docker build --check "$W"
else
  say "- no daemon: pulls skipped"
fi

hdr "5. Routes that need no daemon"
thead
cd "$W" || exit 1
if command -v go >/dev/null 2>&1; then
  row crane-install env GOBIN="$W/bin" go install "github.com/google/go-containerregistry/cmd/crane@$CRANE_VER"
  row crane-export-hadolint bash -c "'$W/bin/crane' export --platform linux/amd64 hadolint/hadolint:$HADOLINT_TAG - | tar -xf - bin/hadolint && ./bin/hadolint --version"
  row crane-hadolint-run bash -c "./bin/hadolint '$W/Dockerfile'"
else
  say "| crane | - | - | no go on PATH | - |"
fi
row pip-hadolint-bin python3 -m pip download -q --no-deps -d "$W/pip" hadolint-bin
row pip-hadolint-py python3 -m pip download -q --no-deps --only-binary=:all: -d "$W/pip" hadolint-py

cd / && rm -rf "$W"
say ""; say "_end of probe_"

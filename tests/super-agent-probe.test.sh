#!/usr/bin/env bash
# super-agent's `probe`, the fixed probe a scratch thread runs on a linked
# machine, driven over the fake machine tools: one JSON line of cores, RAM, live
# load and free RAM, GPU, provider CLIs and gh logins, with a failed GPU read
# told apart from no GPU.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/tools" "$tmp/fake"
for t in bash env jq awk sed grep cat mktemp rm mkdir dirname tr head tail date chmod diff sort wc cut; do ln -s "$(command -v $t)" "$tmp/tools/$t" || exit 2; done
export PATH="$tmp/bin:$tmp/tools" SA_FAKE=$tmp/fake
sa_fake_install "$tmp/bin"
sa_machine laptop 12 32768 "NVIDIA GeForce RTX 2070"; sa_load 1.25 12288; sa_github alice bob
rm -f "$tmp/bin/codex"
probe() { bash "$s/probe.sh" --json; }

out=$(probe); rc=$?
check_rc "a probe exits 0" 0 "$rc"
check "it is one line" 1 "$(grep -c '' <<<"$out")"
check "cores, RAM, live load and free RAM" '{"cores":12,"ram_gb":32,"load1":1.25,"free_gb":12}' "$(jq -c '{cores, ram_gb, load1, free_gb}' <<<"$out")"
check "the GPU" '{"gpu":"NVIDIA GeForce RTX 2070","gpu_failed":false}' "$(jq -c '{gpu, gpu_failed}' <<<"$out")"
check "a provider CLI is a boolean, installed or not" '{"claude":true,"codex":false,"agy":true,"gh":true,"bun":false}' "$(jq -c .clis <<<"$out")"
check "the gh logins this machine holds" '["alice","bob"]' "$(jq -c .gh_logins <<<"$out")"
check "no host name, user or key is in the line" 0 "$(jq '[.. | strings | select(test("laptop|@"))] | length' <<<"$out")"
sa_machine laptop 12 32768
check "no nvidia-smi is no GPU, not a failed read" '{"gpu":null,"gpu_failed":false}' "$(probe | jq -c '{gpu, gpu_failed}')"
sa_gpu_failing
check "an nvidia-smi that fails is a failed read" '{"gpu":null,"gpu_failed":true}' "$(probe | jq -c '{gpu, gpu_failed}')"
rm -f "$tmp/bin/gh"
check "a machine with no gh holds no login" '[]' "$(probe | jq -c .gh_logins)"
rm -f "$tmp/bin/nproc"
out=$(probe 2>/dev/null); rc=$?
check_rc "a machine that cannot be sized exits 2" 2 "$rc"
check "naming the failed tool" "nproc failed: cannot size this machine" "$(jq -r .error <<<"$out")"

finish

#!/usr/bin/env bash
# Usage: gpu-sample.sh <engine> <out-name> [args...]: one 60 s render with GPU sampled every 500 ms.
# Prints peak GPU utilisation, mean utilisation, and peak memory used (MiB) during the render.
here="$(cd "$(dirname "$0")" && pwd)"
samples="$here/logs/$2.gpu.csv"
nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader,nounits -lms 500 >"$samples" &
smi=$!
bash "$here/render-one.sh" "$@"
kill "$smi"
awk -F', ' '{u+=$1; n++; if($1>pu)pu=$1; if($2>pm)pm=$2; if(n==1)base=$2} END{printf "gpu util peak %d%% mean %.0f%%, mem peak %d MiB (first sample %d MiB)\n", pu, u/n, pm, base}' "$samples"

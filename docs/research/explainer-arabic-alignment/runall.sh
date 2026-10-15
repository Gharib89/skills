#!/usr/bin/env bash
# Every timed run of #684, GPU first, then CPU. Run from this folder after build_clips.py.
set -x
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
export LD_LIBRARY_PATH=$PWD/.venv/lib/python3.11/site-packages/nvidia/cublas/lib:$PWD/.venv/lib/python3.11/site-packages/nvidia/cudnn/lib
P=.venv/bin/python
$P align_run.py mms cuda
$P align_run.py egy cuda
$P whisper_run.py deepdml/faster-whisper-large-v3-turbo-ct2 cuda float16 '*.wav' script
$P whisper_run.py Systran/faster-whisper-large-v3 cuda float16
$P whisper_run.py Systran/faster-whisper-small cuda float16
$P whisper_run.py Systran/faster-whisper-medium cuda float16
$P align_run.py mms cpu
$P align_run.py egy cpu
$P whisper_run.py deepdml/faster-whisper-large-v3-turbo-ct2 cpu int8
$P whisper_run.py Systran/faster-whisper-small cpu int8

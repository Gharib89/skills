# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = [
#   "numpy==2.5.4",
#   "onnx==1.23.2",
#   "onnxruntime==1.31.0",
#   "torch==2.14.1",
#   "transformers==5.19.0",
# ]
#
# [tool.uv.sources]
# torch = { index = "pytorch-cpu" }
#
# [[tool.uv.index]]
# name = "pytorch-cpu"
# url = "https://download.pytorch.org/whl/cpu"
# explicit = true
# ///
"""Maintainer only: rebuild the Egyptian Arabic aligner the skill downloads.

    uv run maintainer/export-arabic-aligner.py <out-dir>

Exports IbrahimAmin/egyptian-arabic-wav2vec2-xlsr-53 at a fixed revision to
ONNX (input `audio` [1, n], already normalised to zero mean and unit variance
the way the backend does it; output `logits` [1, t, 43]), quantises its
weights to uint8, and writes `<out-dir>/onnx/model_int8.onnx` and
`<out-dir>/vocab.json`: the layout the backend's aligner reads, and what the
Hugging Face repo agharib/egyptian-arabic-wav2vec2-xlsr-53-onnx hosts.

At these pins the export is byte for byte the hosted file, sha256
2d8525c7b0e27eff0d43aa061c440b95105ce994f0c76f398e75a4d7659bbcc6, so a
changed pin is checked against that sum.
stdout: `export: <path> <sha256>`
"""

import hashlib
import pathlib
import sys

import torch
from huggingface_hub import hf_hub_download
from onnxruntime.quantization import QuantType, quantize_dynamic
from transformers import Wav2Vec2ForCTC

SOURCE = "IbrahimAmin/egyptian-arabic-wav2vec2-xlsr-53"
REVISION = "c2ce8d4d8d548a21c6ea88d5506cb3cf4508a654"


def main(out):
    model = Wav2Vec2ForCTC.from_pretrained(SOURCE, revision=REVISION).eval()
    (out / "onnx").mkdir(parents=True, exist_ok=True)
    fp32 = out / "onnx" / "model_fp32.onnx"
    torch.onnx.export(
        model,
        (torch.zeros(1, 16000),),
        fp32,
        input_names=["audio"],
        output_names=["logits"],
        dynamic_axes={"audio": {1: "n"}, "logits": {1: "t"}},
        opset_version=17,
        dynamo=False,
    )
    int8 = out / "onnx" / "model_int8.onnx"
    quantize_dynamic(fp32, int8, weight_type=QuantType.QUInt8)
    fp32.unlink()
    vocab = hf_hub_download(SOURCE, "vocab.json", revision=REVISION)
    (out / "vocab.json").write_bytes(pathlib.Path(vocab).read_bytes())
    print(f"export: {int8} {hashlib.sha256(int8.read_bytes()).hexdigest()}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: uv run export-arabic-aligner.py <out-dir>")
    main(pathlib.Path(sys.argv[1]))

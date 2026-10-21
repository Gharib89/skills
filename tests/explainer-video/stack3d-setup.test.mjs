// The setup stage through its process door: the `gpu-3d` row the `stack3d`
// component needs. It is opt-in, downloads nothing (three arrives with
// npm-packages), and is present only where an NVIDIA card answers.
import { test } from "node:test";
import assert from "node:assert/strict";
import { calls, fixture, machine, realRows, row, run } from "./setup-lib.mjs";

const ID = "gpu-3d";

test("an NVIDIA card makes the opt-in row present, and it is listed only when asked for", () => {
  const fx = fixture(realRows());
  const all = run(fx, ["check", "--all"], "ffmpeg", machine(7.5));
  assert.equal(row(all.out, ID)[2], "present", all.out);
  const plain = run(fx, ["check"], "ffmpeg", machine(7.5));
  assert.equal(row(plain.out, ID), undefined, plain.out);
});

test("with no card, or a failed probe, the row is refused with the reason a run repeats", () => {
  const cases = {
    "no card": [machine(null), /no card found/],
    "a failed probe": [
      { EXPLAINER_VIDEO_FAKE_GPU: "failed" },
      /nvidia-smi failed/,
    ],
  };
  for (const [what, [env, why]] of Object.entries(cases)) {
    const r = run(fixture(realRows()), ["check", "--all"], "ffmpeg", env);
    const status = row(r.out, ID)[2];
    assert.match(status, /^refused: unavailable without an NVIDIA GPU/, what);
    assert.match(status, why, what);
  }
});

test("install downloads nothing for the row, on a card or off one", () => {
  for (const env of [machine(7.5), machine(null)]) {
    const fx = fixture(realRows());
    run(fx, ["install", "--all"], "ffmpeg", env);
    assert.ok(calls(fx).length > 0, "install ran other rows");
    assert.equal(
      calls(fx).filter((c) => JSON.stringify(c).includes(ID)).length,
      0,
    );
  }
});

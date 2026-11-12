// The determinism gate's judgment: the sample frames taken in two launches
// must match by pixels. A frame that differs is re-checked before it counts,
// that one time alone in two fresh launches, and is a finding only if those two
// differ too: a launch of many times can differ on a scene's last frame where
// the same frame alone never does (#1170).

// `launch(dir, times)` snapshots `times` into the frames cache folder `dir` and
// answers `[time, pixels, path]` for each; `fail(why)` ends the stage. Answers the
// findings and the first launch's frames, which the critic judges.
export async function determinismFindings(launch, sampled, sceneAt, fail) {
  const [a, b] = [await launch("a", sampled), await launch("b", sampled)];
  if (a.length !== sampled.length || b.length !== sampled.length)
    fail(
      `snapshot gave ${a.length} and ${b.length} of ${sampled.length} frames`,
    );
  const findings = [];
  for (const [i, [t, pixels]] of a.entries()) {
    if (pixels === b[i][1]) continue;
    const again = [];
    for (const n of [1, 2]) {
      const taken = await launch(`recheck-${i}-${n}`, [t]);
      if (taken.length !== 1)
        fail(`snapshot gave ${taken.length} of 1 frame for a re-check`);
      again.push(taken[0]);
    }
    // A frame that repeats alone replaces launch a's, so the critic judges,
    // and keys its verdict on, the stable frame.
    if (again[0][1] === again[1][1]) a[i] = again[0];
    else
      findings.push(
        `${t.toFixed(2)} s ${sceneAt(t)}: the frame differs between two launches and between two single-frame re-checks`,
      );
  }
  return { findings, first: a };
}

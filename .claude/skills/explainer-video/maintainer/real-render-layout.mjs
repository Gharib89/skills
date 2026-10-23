// Maintainer only: the layout gate over the samples of each scene of one
// composition on the real backend, as the gates stage takes them: its text
// inside the safe area, none clipped, small or stacked. An excerpt's sentences,
// each one reading box, are judged on their words as the gates stage judges a
// scene's text.
import { sceneEvents } from "../scripts/gates/events.mjs";
import { readingFindings } from "../scripts/gates/reading.mjs";
import { judge } from "../scripts/lib/layout.mjs";
import { sampleTimes } from "../scripts/lib/motion.mjs";
import { floors } from "../scripts/lib/style.mjs";
import { FPS } from "../scripts/render/compose.mjs";

// `run` is a composed fixture part (`comp`, `scenes`), `raw` its events and
// `excerpts` the ids of its excerpt scenes. Returns each scene's layout findings
// `[id, samples, findings]` and each excerpt's reading findings `[id, findings]`.
export async function layoutFindings({
  run,
  raw,
  excerpts,
  backend,
  env,
  profile,
}) {
  const { times: eventTimes, moving } = sceneEvents(raw, run.scenes);
  const laid = [];
  const reads = [];
  for (const sc of run.scenes) {
    const times = sampleTimes({ ...sc, fps: FPS, events: eventTimes });
    const findings = [];
    const frames = await backend.probe(run.comp, times, { env });
    judge(
      await backend.check(run.comp, times, { env }),
      frames,
      floors(profile),
      // a finding is the scene's while its time is, as the gates stage files it
      (gate, t, what) => {
        if (
          gate === "layout" &&
          t >= sc.start - 1e-6 &&
          t < sc.start + sc.duration - 1e-6
        )
          findings.push(`${t.toFixed(2)} s: ${what}`);
      },
      moving,
    );
    laid.push([sc.id, times.length, [...new Set(findings)]]);
    if (excerpts.includes(sc.id))
      reads.push([
        sc.id,
        readingFindings(
          { sc, times, end: sc.start + sc.duration },
          frames,
          moving,
        ),
      ]);
  }
  return { laid, reads };
}

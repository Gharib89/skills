// The joins gate of an Arabic run, judged on the probe's joins measure
// (lib/backend/joins.mjs) at each scene's samples: a word whose pieces, each
// shaped alone in the face Chrome drew it in, differ from the word shaped
// whole is drawn unjoined. What shaping cannot judge (a face with no file, a
// reversed Latin or digit run) is the critic's to check, under its rtl kind.

// Each broken word handed to `add(t, scene, what)`; returns the number of
// words shaped and the critic's checks, each scene's lines once.
export function joinsFindings(plan, frames, add) {
  const asks = {};
  let shaped = 0;
  for (const p of plan)
    for (const t of p.samples) {
      const j = frames.find((f) => f.t === t).joins;
      if (!j) continue;
      shaped += j.checked;
      for (const b of j.broken)
        add(t, p.sc.id, `"${b.word}" breaks its joins in ${b.face}`);
      for (const a of j.asks) (asks[p.sc.id] ??= new Set()).add(a.what);
    }
  const checks = Object.fromEntries(
    Object.entries(asks).map(([id, whats]) => [id, [...whats]]),
  );
  return { shaped, checks };
}

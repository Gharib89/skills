// The critic's verdict format, and the check that refuses a verdict outside it.
export const KINDS = ["unreadable", "invented"];
export const SCORES = ["clarity", "legibility", "fit", "motion"];

// `bad(why)` stops the run; `sc` is the timeline scene the verdict judges.
export function checkVerdict(v, sc, bad) {
  if (!Array.isArray(v?.failures)) bad("no failures list");
  v.failures.forEach((x, i) => {
    if (!KINDS.includes(x?.kind))
      bad(`failure ${i + 1} kind "${x?.kind}" is not ${KINDS.join(" or ")}`);
    if (typeof x.what !== "string" || !x.what.trim())
      bad(`failure ${i + 1} says nothing`);
  });
  for (const k of SCORES)
    if (![1, 2, 3, 4, 5].includes(v.scores?.[k]))
      bad(`score ${k} is not a whole number 1 to 5`);
  if (!Array.isArray(v.worst)) bad("no worst list");
  if (v.worst.length > 3)
    bad(`worst holds ${v.worst.length} entries, at most 3`);
  v.worst.forEach((x, i) => {
    if (!x || typeof x !== "object") bad(`worst ${i + 1} is not an object`);
    if (!(
      Number.isFinite(x?.at) &&
      x.at >= +sc.start.toFixed(3) &&
      x.at <= +(sc.start + sc.duration).toFixed(3)
    ))
      bad(`worst ${i + 1} at ${x?.at} is not a time inside the scene`);
    for (const k of ["what", "evidence", "fix"])
      if (typeof x[k] !== "string" || !x[k].trim())
        bad(`worst ${i + 1} has no ${k}`);
  });
}

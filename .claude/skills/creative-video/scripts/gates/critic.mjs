// The critic gate: a Claude subagent per scene (agents/critic.md) reads the
// scene's sample stills, the narration and the excerpts it cites, describes
// each still as a stranger would, and names any hard failure. It gives no
// scores. Carried from explainer-video's critic, its rounds and its batching.
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

export const KINDS = ["unreadable", "invented", "rtl"];
const KIND_LIST = `${KINDS.slice(0, -1).join(", ")} or ${KINDS.at(-1)}`;
// Bumped when the verdict's format or what the critic reads changes, so a
// verdict in the old one is judged again rather than refused or kept.
const FORMAT = 2;
const ROUNDS = 2;

// `bad(why)` stops the run; `times` are the scene's still times in order.
export function checkVerdict(v, times, bad) {
  if (!v || typeof v !== "object" || Array.isArray(v)) bad("is not an object");
  for (const k of Object.keys(v))
    if (k === "scores")
      bad(
        "scores is not part of a verdict: describe each still, never score it",
      );
    else if (!["stills", "failures"].includes(k))
      bad(`${k} is not part of a verdict`);
  if (!Array.isArray(v.stills) || v.stills.length !== times.length)
    bad(
      `stills holds ${v.stills?.length ?? 0} description(s), one per still: ${times.length}`,
    );
  v.stills.forEach((s, i) => {
    if (s?.t !== times[i]) bad(`still ${i + 1} t is not ${times[i]}`);
    if (typeof s.sees !== "string" || !s.sees.trim())
      bad(`still ${i + 1} describes nothing`);
  });
  if (!Array.isArray(v.failures)) bad("no failures list");
  v.failures.forEach((x, i) => {
    if (!KINDS.includes(x?.kind))
      bad(`failure ${i + 1} kind "${x?.kind}" is not ${KIND_LIST}`);
    if (typeof x.what !== "string" || !x.what.trim())
      bad(`failure ${i + 1} says nothing`);
  });
}

const hash = (...v) =>
  crypto
    .createHash("sha256")
    .update(JSON.stringify(v))
    .digest("hex")
    .slice(0, 16);

// The critic gate's record for gates.json. `plan` is the gates' scenes with
// their sample times, `stills` maps a sample time to `{ pixels, path }` from
// the first snapshot launch, `checks` maps a scene to what the gates measured
// but could not judge, for the critic's rtl kind (checks.json beside the
// stills), `prev` the critic's last record when the voice is the same (rounds
// count per voice), `fail` refuses a malformed verdict.
export function criticGate({
  run,
  plan,
  stills,
  script,
  pack,
  checks = {},
  prev,
  fail,
}) {
  // Every critic reads every scene's narration and every cited excerpt, so a
  // scene's key takes all of them beside its own stills.
  const text = new Map((pack?.excerpts ?? []).map((x) => [x.id, x.text]));
  const read = script.scenes.map((s) => [
    s.narration,
    (s.cites ?? []).map((ids) => ids.map((id) => [id, text.get(id)])),
  ]);
  const keys = Object.fromEntries(
    plan.map((p) => [
      p.sc.id,
      hash(
        p.sc.id,
        p.samples.map((t) => stills.get(t).pixels),
        read,
        checks[p.sc.id] ?? [],
        FORMAT,
      ),
    ]),
  );
  const key = hash(keys);
  const dirOf = (k) => path.posix.join(".cache", "critic", k);
  const sameFormat = prev?.format === FORMAT;
  const rounds = sameFormat ? [...prev.rounds] : [];
  const dir = dirOf(key);
  // Past two rounds a render carries the second round's verdict: no stills.
  if (rounds.includes(key) || rounds.length < ROUNDS) {
    const abs = path.join(run, dir);
    fs.mkdirSync(abs, { recursive: true });
    const set = {};
    for (const p of plan)
      set[p.sc.id] = p.samples.map((t, i) => {
        const file = `${p.sc.id}.${i + 1}.png`;
        fs.copyFileSync(stills.get(t).path, path.join(abs, file));
        return { t, file };
      });
    fs.writeFileSync(path.join(abs, "stills.json"), JSON.stringify(set));
    fs.writeFileSync(path.join(abs, "keys.json"), JSON.stringify(keys));
    fs.writeFileSync(path.join(abs, "checks.json"), JSON.stringify(checks));
    // The last round's verdict on a scene whose key is unchanged is carried,
    // so only changed scenes are pending.
    const before = sameFormat && prev.stills !== dir ? prev.stills : null;
    const beforeKeys = before && path.join(run, before, "keys.json");
    if (beforeKeys && fs.existsSync(beforeKeys)) {
      const old = JSON.parse(fs.readFileSync(beforeKeys, "utf8"));
      for (const p of plan) {
        const from = path.join(run, before, `${p.sc.id}.json`);
        const to = path.join(abs, `${p.sc.id}.json`);
        if (
          old[p.sc.id] === keys[p.sc.id] &&
          fs.existsSync(from) &&
          !fs.existsSync(to)
        )
          fs.copyFileSync(from, to);
      }
    }
  }
  const verdicts = (k) =>
    plan.map((p) => {
      const f = path.join(run, dirOf(k), `${p.sc.id}.json`);
      if (!fs.existsSync(f)) return null;
      const bad = (why) => fail(`critic verdict ${p.sc.id}.json: ${why}`);
      let v;
      try {
        v = JSON.parse(fs.readFileSync(f, "utf8"));
      } catch (e) {
        bad(e.message);
      }
      checkVerdict(v, p.samples, bad);
      return { ...v, id: p.sc.id, start: p.sc.start };
    });
  let judged;
  const own = verdicts(key);
  if (own.every(Boolean) && (rounds.includes(key) || rounds.length < ROUNDS)) {
    if (!rounds.includes(key)) rounds.push(key);
    judged = { vs: own, round: rounds.indexOf(key) + 1 };
  } else if (rounds.length >= ROUNDS) {
    const vs = verdicts(rounds[ROUNDS - 1]);
    if (vs.every(Boolean)) judged = { vs, round: ROUNDS, carried: true };
  }
  const floor = `no ${KIND_LIST} content`;
  const base = { floor, rounds, format: FORMAT };
  if (!judged)
    return {
      ...base,
      status: "pending",
      measured: `round ${rounds.length + 1} of ${ROUNDS}, ${own.filter(Boolean).length} of ${own.length} scene(s) judged, stills in ${dir}`,
      evidence: [],
      stills: dir,
    };
  const { vs, round, carried } = judged;
  // Led by the scene's start, as layout's lines are.
  const evidence = vs.flatMap((v) =>
    v.failures.map(
      (x) => `${v.start.toFixed(2)} s ${v.id}: ${x.kind}: ${x.what}`,
    ),
  );
  return {
    ...base,
    status: evidence.length ? "fail" : "pass",
    measured: `${evidence.length} finding(s)${evidence.length ? `, first: ${evidence[0]}` : ""}, round ${round} of ${ROUNDS}${carried ? ", carried: no third round" : ""}`,
    evidence,
    stills: dirOf(carried ? rounds[ROUNDS - 1] : key),
    // The final round's red is final: no later round can judge a fix.
    final: evidence.length > 0 && round === ROUNDS,
    described: vs.map((v) => ({ scene: v.id, stills: v.stills })),
  };
}

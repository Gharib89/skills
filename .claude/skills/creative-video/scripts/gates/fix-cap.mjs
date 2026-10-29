// The fix cap of one gates run (gates/gates.mjs): its count of fix attempts,
// and the summary line the run prints last.

const MAX_ATTEMPTS = 2;

// The fix cap: a red run on one voice is one fix attempt, the same inputs
// judged again are none, and a pass or a new voice starts the count again. The
// voice, not script.json: the gates judge the voiced words, so a script edited
// without voicing again changes nothing they judge. A critic still to judge is
// no pass, and the critic's red second round is final.
export function fixAttempts({
  gates,
  failing,
  pending,
  sameVoice,
  prev,
  inputs,
}) {
  return gates.critic.final
    ? MAX_ATTEMPTS + 1
    : !failing
      ? pending && sameVoice
        ? (prev.attempts ?? 0)
        : 0
      : sameVoice && prev.inputs === inputs
        ? Math.max(prev.attempts ?? 0, 1)
        : (sameVoice ? (prev.attempts ?? 0) : 0) + 1;
}

// `gates: <n> pass, <m> fail[, 1 pending]` and what comes next. A check run
// writes no gates.json, so its red names no fix attempt.
export function summaryLine({ gates, failing, pending, attempts, check }) {
  return `gates: ${Object.keys(gates).length - failing - pending} pass, ${failing} fail${
    pending ? ", 1 pending" : ""
  }${
    gates.critic.final
      ? "; stop: the critic's second round is red, no video"
      : failing && !check
        ? attempts > MAX_ATTEMPTS
          ? "; stop: red after two fix attempts, no video"
          : `; next: fix attempt ${attempts} of ${MAX_ATTEMPTS}`
        : pending
          ? `; next: run the critic, round ${gates.critic.rounds.length + 1} of 2`
          : ""
  }${check ? "; check run: gates.json not written" : ""}`;
}

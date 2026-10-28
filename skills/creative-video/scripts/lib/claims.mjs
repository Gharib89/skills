// What the narration claims, defined once so the script check that judges it
// and the gates that refuse an unjudged one cannot drift apart.
import crypto from "node:crypto";

// The scenes' sentences, their cites and the cited excerpts' words, hashed:
// a sentence or a cite changed, or an excerpt re-packed, is other claims.
export function claimsKey(script, pack) {
  const text = new Map(pack.excerpts.map((x) => [x.id, x.text]));
  return crypto
    .createHash("sha256")
    .update(
      JSON.stringify(
        script.scenes.map((s) => [
          s.id,
          s.narration,
          s.cites ?? null,
          (s.cites ?? []).map((ids) => ids.map((id) => text.get(id) ?? null)),
        ]),
      ),
    )
    .digest("hex")
    .slice(0, 16);
}

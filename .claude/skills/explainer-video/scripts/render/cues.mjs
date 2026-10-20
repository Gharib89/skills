// The caption cues of a render: a cue breaks at a sentence end, or before a
// token that would take it past CUE_CHARS; it shows until the next cue in its
// scene starts.
import { CUE_CHARS } from "./compose.mjs";

const r3 = (n) => +n.toFixed(3);

// `script` is script.json's scenes, `scenes` the timeline's by the same index.
export function captionCues(script, scenes) {
  const cues = [];
  script.forEach((s, i) => {
    const sc = scenes[i];
    const own = [];
    let w = 0;
    for (const tokens of s.captions) {
      let cue = null;
      for (const t of tokens) {
        const token = {
          text: t.text,
          start: sc.words[w].start,
          end: sc.words[w + t.words - 1].end,
        };
        w += t.words;
        if (cue && `${cue.text} ${t.text}`.length > CUE_CHARS) cue = null;
        if (cue) {
          cue.text += ` ${t.text}`;
          cue.tokens.push(token);
        } else {
          cue = { text: t.text, tokens: [token] };
          own.push(cue);
        }
      }
    }
    own.forEach((c, k) => {
      c.start = c.tokens[0].start;
      c.end =
        own[k + 1]?.tokens[0].start ??
        r3(Math.min(c.tokens.at(-1).end + 0.3, sc.start + sc.duration));
    });
    cues.push(...own);
  });
  return cues;
}

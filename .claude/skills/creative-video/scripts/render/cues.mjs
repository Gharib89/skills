// The caption cues of a render: a cue breaks at a sentence end, or before a
// token that would take it past CUE_CHARS; it shows until the next cue in its
// scene starts.

// Sized for a 40 px Inter caption 1680 px wide, about 70 characters a line, so
// 84 is at most two lines.
export const CUE_CHARS = 84;

const r3 = (n) => +n.toFixed(3);

// `script` is each scene's `captions`, a token list per sentence, and
// `speakers`, a role per sentence; `scenes` the timeline's by the same index.
// In a video of two or more speakers, a cue whose speaker is not the last
// cue's opens with `<Role>: `, its `who`, which counts toward CUE_CHARS; a cue
// never spans two sentences, so never two speakers.
export function captionCues(script, scenes) {
  const cues = [];
  const many = new Set(script.flatMap((s) => s.speakers ?? [])).size > 1;
  let last = null;
  script.forEach((s, i) => {
    const sc = scenes[i];
    const own = [];
    let w = 0;
    for (const [k, tokens] of s.captions.entries()) {
      const speaker = s.speakers?.[k];
      let who =
        many && speaker !== last
          ? speaker[0].toUpperCase() + speaker.slice(1)
          : undefined;
      last = speaker;
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
          cue = who
            ? { who, text: `${who}: ${t.text}`, tokens: [token] }
            : { text: t.text, tokens: [token] };
          who = undefined;
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

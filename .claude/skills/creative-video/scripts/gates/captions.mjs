// The caption reading: the cues the composition draws and the findings the
// timeline's words, those cues and the SRT leave between them.
import { CUE_CHARS } from "../render/cues.mjs";

const r3 = (n) => +n.toFixed(3);

const unescape = (s) =>
  s
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&quot;", '"')
    .replaceAll("&amp;", "&");
// Each cue's start, end and text as drawn: a speaker's name (render/cues.mjs)
// is its `who` and its text's `<Role>: ` prefix, never one of its words.
export const cuesOf = (html) =>
  [
    ...html.matchAll(
      /<div class="cue clip" data-start="([\d.]+)" data-duration="([\d.]+)"[^>]*>(.*?)<\/div>/g,
    ),
  ].map((m) => {
    const words = [...m[3].matchAll(/<span class="w"[^>]*>(.*?)<\/span>/g)]
      .map((w) => unescape(w[1].replace(/<[^>]+>/g, "")))
      .join(" ");
    const who = m[3].match(/<span class="who">(.*?):<\/span>/)?.[1];
    const cue = { start: +m[1], end: +m[1] + +m[2] };
    return who
      ? { ...cue, who: unescape(who), text: `${unescape(who)}: ${words}` }
      : { ...cue, text: words };
  });

// The timeline's words, the composition's cues, and the SRT as the cues' copy.
export function captionFindings({ timeline, cues, srtText }) {
  const caps = [];
  const eps = 1e-6;
  // Word times are 3-place values and a scene's start is truncated to 6, so
  // a word on the scene's first frame reads half a millisecond early.
  const edge = 5e-4;
  for (const sc of timeline.scenes)
    sc.words.forEach((w, i) => {
      const at = `word ${i + 1} "${w.text}" of ${sc.id}`;
      if (!(w.start < w.end)) caps.push(`${at} does not start before it ends`);
      if (i && w.start < sc.words[i - 1].end - eps)
        caps.push(`${at} starts before the word before it ends`);
      if (w.start < sc.start - edge || w.end > sc.start + sc.duration + edge)
        caps.push(`${at} falls outside its scene`);
    });
  cues.forEach((c, i) => {
    const at = `cue ${i + 1}`;
    if (!c.text.trim() || !(c.start < c.end)) caps.push(`${at} is empty`);
    if (c.text.length > CUE_CHARS)
      caps.push(`${at} holds ${c.text.length} characters, over ${CUE_CHARS}`);
    if (i && c.start < cues[i - 1].end - eps)
      caps.push(`${at} starts before cue ${i} ends`);
    if (c.end > timeline.total + 0.001)
      caps.push(`${at} runs past the video's ${timeline.total} s`);
  });
  const seconds = (t = "") => {
    const m = t.trim().match(/^(\d+):(\d\d):(\d\d)[,.](\d{3})$/);
    return m ? +m[1] * 3600 + +m[2] * 60 + +m[3] + +m[4] / 1000 : NaN;
  };
  const srt = srtText
    .trim()
    .split(/\r?\n\r?\n/)
    .filter(Boolean)
    .map((b) => {
      const [, times = "", ...text] = b.split(/\r?\n/);
      const [a, z] = times.split(" --> ");
      return { start: seconds(a), end: seconds(z), text: text.join(" ") };
    });
  if (srt.length !== cues.length)
    caps.push(
      `the SRT holds ${srt.length} cue(s), the composition ${cues.length}`,
    );
  else
    srt.forEach((s, i) => {
      const c = cues[i];
      if (s.text !== c.text)
        caps.push(
          `SRT cue ${i + 1} reads "${s.text}", the composition "${c.text}"`,
        );
      if (!(
        Math.abs(s.start - c.start) <= 0.001 + eps &&
        Math.abs(s.end - c.end) <= 0.001 + eps
      ))
        caps.push(
          `SRT cue ${i + 1} runs ${s.start}-${s.end} s, the composition ${r3(c.start)}-${r3(c.end)} s`,
        );
    });
  return caps;
}

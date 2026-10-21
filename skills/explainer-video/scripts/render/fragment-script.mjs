// The lines of a scene's script that run a custom scene's fragment script: the
// declared cues resolved to seconds, then the fragment's own lines called as
// `(tl, cue, $, duration)` on the scene's paused timeline (lib/fragment.mjs
// holds the contract). `$(sel)` is the selector scoped to the scene and `$()`
// the scene's content.
export const fragmentScript = (scope, script, cues, duration) =>
  script.trim()
    ? `
        const cues = ${JSON.stringify(cues)};
        ((tl, cue, $, duration) => {
${script}
        })(tl, (name) => cues[name], (sel) => ${JSON.stringify(scope)} + (sel ? " " + sel : " .content"), ${duration});`
    : "";

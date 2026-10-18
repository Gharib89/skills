# Explainer section join (PROTOTYPE, never merged)

Throwaway prototype for the wayfinder ticket
[Section join: render a long video per section and concat](https://github.com/Gharib89/skills/issues/794).
It cuts dora-core's first 12 scenes into three sections, renders each on its
own, joins them, and measures the join against the same scenes rendered whole.

## What is here

- `build.mjs`: writes `naive/` (scenes timed as the composer times them) and
  `snapped/` (every scene's duration rounded up to whole frames, the narration
  padded to match), each with `whole/` and sections `s1/ s2/ s3/`.
- `hf.mjs`: one `hyperframes render` with the composer's flags.
- `bench.sh`: renders all of them, a second `snapped/s2`, an edited
  `snapped/s2edit`, and the snapped set losslessly (`--crf 0`).
- `analyze.py`: concat with `-c copy`, framemd5, pts and keyframes, captions
  band, chapters, audio mixed once against per-section AAC.
- `gate.mjs`: the determinism gate's frame check against each section.
- `page.html`: the published page's source (frames inlined at publish).

## Run

```sh
node build.mjs <dora-core composition dir> <work>
./bench.sh <work>
uv run --with numpy python -I analyze.py <work> > results.json
node gate.mjs <work>
```

Measured output: `results.json`, `results-lossless.txt`, `bench.jsonl`,
`plan.json`. Published page: see the ticket's resolution comment.

# Parts

A request over 5 minutes is offered a split into **parts**, each its own video
of 2 to 5 minutes. The offer comes once the source stage is done, because the
part plan divides the pack's excerpts. The operator's yes or no decides: no
part is made unasked, and a request of 5 minutes or less is never offered one.

## Offer

`node <skill>/scripts/parts/parts.mjs explainers/<slug> offer` prints the fewest
parts that fit (`parts offer: 12 min is over 5: 3 parts of 4 + 4 + 4 min, or one
long video in sections`) and the estimate of both shapes (`parts estimate:
...`): the render and gates time of all parts and of the first, and of one long
video.
Narration time is not in it. At 5 minutes or less it prints `parts: no offer`:
go on to Script. Put the offer and both estimates to the operator in one
question and take the answer.

- **No.** `parts.mjs <run> decline` records it and prints one line with the
  estimate. Go on to Script as one long video in sections, and ask nothing more.
- **Yes**, with or without edits. Write `explainers/<slug>/parts.json`, then run
  `parts.mjs <run> check` until it passes.

## The part plan

```json
{
  "parts": [
    {
      "title": "Claiming work",
      "focus": "what happens before the first edit",
      "minutes": 4,
      "excerpts": ["ex-1", "ex-2"],
      "must": ["local gate"]
    }
  ]
}
```

Each part has a title, a focus, 2 to 5 minutes and at least one excerpt, and no
excerpt sits in two parts. The minutes add up to the brief's length within
0.05 minute. A part's `must` items come from the brief's, and every brief
`must` item lands in a part. `check` prints one line a part, then
`parts: <n> parts, <m> min`, or refuses with `parts: <why>`.

## A part

`parts.mjs <run> start <n>` makes part `n`'s folder, `parts/<nn>-<title>/`, a
run folder like any other: every stage script runs on it unchanged. It holds the
brief (the run's own, with the part's focus, length and `must`), the part's
excerpts plus the part before it, and `part.json` (the series, the number, the
bridge back, the next part's title, the operator's notes). Part `n` starts only
once part `n-1` is delivered. The command prints the bridge, the next part and
each note it carries over: the scene notes, kept-term changes and brief changes
from the previous part's latest board answers. Take them into the new part's
script.

The source pack stays with the run: a part's cites read word for word in the
run's snapshots, and its style comes from the same `explainers/.styles/`.

Run Script, Voice, Storyboard and Render on the part's folder, in order, and
finish each part before the next starts. The script gates hold what a part owes
on top of the rest, the `parts` gate:

- its hook and its recap, like any video: it stands alone.
- from part 2, the `context` scene cites at least one excerpt of the part
  before: its bridge.
- except the last part, the `end` scene names the next part by its title.

## Delivery

Each part's render puts `<nn>-<title>.mp4`, `.srt` and `.png` (its poster) into
`explainer-video/<repo>/<slug>/` of the videos folder: one folder for the whole
series, one numbered file a part. The run folder holds `parts.json` and one
folder a part under `parts/`. The part's own `out/` keeps `poster.png`.

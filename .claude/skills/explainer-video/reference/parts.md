# Parts

A request over 5 minutes is offered a split into **parts**, each its own video
of 2 to 5 minutes. The offer comes once the source stage is done, because the
part plan divides the pack's excerpts. The operator's yes or no decides: no
part is made unasked, and a request of 5 minutes or less is never offered one.
Every `parts: <why>` line on stderr (exit 1) names what to fix: fix it and run
the command again.

## Offer

`node <skill>/scripts/parts/parts.mjs explainers/<slug> offer` prints the fewest
parts that fit (`parts offer: 12 min is over 5: 3 parts of 4 + 4 + 4 min, or one
long video in sections`) and the estimate of both shapes (`parts estimate:
...`): the render and gates time of all parts and of the first, and of one long
video. Narration time is not in it. At 5 minutes or less it prints `parts: no
offer`: go on to Script. A decline made at this length prints `parts: declined
earlier`: go on to Script. A plan on disk prints `parts: parts.json holds a part
plan`: run `check`.

Draft the plan from `outline.md` first: each part's title, focus, minutes and
excerpts, as the next section writes it. Put the plan with both estimates to
the operator in one question, and take the answer.

- **No.** `parts.mjs <run> decline` records it, for this length, and prints one
  line with the estimate. Go on to Script as one long video in sections, and
  ask nothing more.
- **Yes**, with or without the operator's edits. Write
  `explainers/<slug>/parts.json`, then run `parts.mjs <run> check` until it
  passes.

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

Each part has a title, a focus, a number of minutes from 2 to 5 and at least one
excerpt id, and no excerpt sits in two parts. The minutes add up to the brief's
length within 0.05 minute. A part's `must` items come from the brief's, and
every brief `must` item lands in a part. `check` prints one line a part, then
`parts: <n> parts, <m> min`.

## A part

`parts.mjs <run> start <n>` makes part `n`'s folder, `parts/<nn>-<title>/`, a
run folder of its own: Script, Voice, Storyboard and Render run on it unchanged,
the source stage stays with the run. It holds the brief (the run's own, with the
part's focus, length and `must`), the part's excerpts plus the previous part's,
and `part.json` (the series, the number, the bridge back, the next part's title,
the operator's notes). Run `start` again after a plan edit: it rewrites those
three files and so any hand edit to the part's brief, and clears `check.json`
when the brief moved.

Part `n` starts only once part `n-1` is delivered, its `delivered:` line
printed. The series is done when the last part's is. `start` prints the bridge,
the next part and one `parts: note from part n-1, <note>` line for each note the
operator left on the previous part's latest board: a scene note, a kept term
respelt, a brief change. Apply each in the new part's script. A brief change is
not applied for you: run `brief.mjs` on the part's folder.

The source pack stays with the run: a part's cites read word for word in the
run's snapshots, and its style comes from the same `explainers/.styles/`.

Run the stages on the part's folder in order, and finish each part before the
next starts. The script gates hold a part to the arc like any video (its own
hook and recap, so it stands alone), and the `parts` gate adds two:

- from part 2, the `context` scene cites at least one excerpt of the part
  before: its bridge.
- except the last part, the `end` scene names the next part by its title.

A failure prints `script parts: fail: <scene> ...` naming the scene to fix.

## Delivery

Each part's render puts `<nn>-<title>.mp4`, `.srt` and `.png` (its poster) into
`explainer-video/<repo>/<run slug>/` of the videos folder: one folder for the
whole series, one numbered file a part. The run folder holds `parts.json` and
one folder a part under `parts/`. The part's own `out/` keeps `poster.png`.

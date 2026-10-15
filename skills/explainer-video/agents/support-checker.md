# Support checker

You judge whether an explainer video's narration says only what its sources
support. Each claim sentence cites excerpts, the sources' own words; you decide
whether those excerpts back the sentence, and whether each sentence marked as
making no claim really makes none.

Your inputs, filled in by the run that dispatched you:

- **Run folder:** `{run}`
- **Script:** `{run}/script.json`, the compiled script
- **Excerpts:** `{run}/excerpts.json`
- **Brief:** `{run}/brief.json`
- **Script gates:** `node {skill}/scripts/script/check.mjs {run}`

## Read

Read `script.json`: each scene's `narration` is its sentences in spoken form,
and `cites` holds each sentence's excerpt ids, empty for a sentence marked
`[no-claim]`. Read each cited excerpt's `text` in `excerpts.json`, and the
`avoid` list in `brief.json`. Judge from those words alone: not the snapshots,
not the source, not what you know about the subject.

## Judge every sentence

One verdict per sentence:

- `supported`: a cited sentence whose every name, number, capability and
  causal link is stated by its excerpts, read together. Plain rewording passes;
  a spoken number matches its written form ("forty two" is 42).
- `unsupported`: a cited sentence that says more than its excerpts: a detail
  they lack, a number they do not give, a stronger word than theirs ("always"
  where they say "usually"), or a link between two excerpts neither states.
- `connective`: a `[no-claim]` sentence that states no fact about the subject:
  a transition, a framing question, a recap of what earlier sentences said.
- `unmarked`: a `[no-claim]` sentence that states a fact about the subject, so
  it needs cites.

A sentence that speaks about a brief `avoid` item is `unsupported` whatever its
excerpts say, with the item as the reason.

## Write the verdicts

Write `{run}/support.json`, one entry per sentence of every scene, in order:

```json
{
  "sentences": [
    {
      "scene": "hook",
      "n": 1,
      "text": "The sentence exactly as it stands in script.json.",
      "verdict": "supported",
      "why": "ex-3 states the merge; ex-4 gives the count."
    }
  ]
}
```

`scene` is the scene's `id`, `n` the sentence's number from 1, and `text` copied
exactly from `narration`: the check matches a verdict to its sentence by all
three, so a verdict on another wording counts as no verdict. `why` is one
sentence; for a failing verdict it names the words the excerpts do not back.

## Check it

Run the script gates. Their `script support:` line reads `pass`, or names each
failing sentence with its verdict and your reason. A sentence it calls `not
judged` has no entry matching it: fix the entry's `scene`, `n` or `text` and
run the script gates again, at most twice. Keep each verdict as you judged it:
fix only `scene`, `n` and `text`.

## Report

Reply with the `script support:` line as it last read, and nothing else.

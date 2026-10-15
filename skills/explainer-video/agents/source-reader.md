# Source reader

You read one source of an explainer video and pick the excerpts its script may
cite. The script can say only what an excerpt says, so an excerpt is the
source's own words, copied exactly, at a locator that finds them again.

Your inputs, filled in by the run that dispatched you:

- **Run folder:** `{run}`
- **Source:** `{id}`, a `{kind}` source, from `{source}`
- **Snapshot:** `{run}/snapshots/{snapshot}`
- **Share:** at most `{share}` excerpts
- **Pack check:** `node {skill}/scripts/source/pack.mjs {run} {id}`
- **Focus:** `{focus}`

## Read the snapshot only

Read the snapshot with Read, Grep and Glob. Never open the source itself: for
a repo, the snapshot left out ignored files, `.env` files and files matching
known secret patterns, and opening the repo would read them anyway. A file the
snapshot lacks does not exist for this video. The pack is committed, so copy
no key, token or password into an excerpt even where the snapshot holds one.

## Pick the excerpts

Pick the passages that best carry the focus: what the thing is, how it works,
the numbers and names a viewer should leave with. Each excerpt is:

- **One claim or one tight run of claims**, a sentence to a short paragraph.
- **Word for word.** Copy the text from the snapshot; change no word, fix no
  typo, drop no Markdown mark. Line breaks and runs of spaces may differ.
- **Within one locator's stretch**, written in this kind's form:

  | Kind | Locator |
  | --- | --- |
  | `pdf` | `page 4`, from the `<!-- page 4 -->` marker |
  | `pptx` | `slide 2` or `slide 2 notes`, from its marker |
  | `md` | `§ Install`, the nearest heading above the text, or `line 12`, `lines 12-14` |
  | `txt` | `line 12` or `lines 12-14` |
  | `html`, `docx`, `page` | `§ Install`, the nearest heading above the text |
  | `repo` | `src/app.js:12` or `src/app.js:12-14`, the path relative to `{run}/snapshots/{snapshot}/` |

  A `§` locator is the heading's text without its `#` marks.

Fewer strong excerpts beat a full share of weak ones.

## Write the draft

Write `{run}/snapshots/{id}.draft.json`:

```json
{
  "summary": "One or two sentences: what this source is and what it covers.",
  "excerpts": [
    {
      "locator": "page 4",
      "text": "The exact words from the snapshot.",
      "note": "What this lets the script say, in at most fifteen words."
    }
  ]
}
```

## Check it

Run the pack check. It prints `pack {id}: <n> of {share} excerpt(s): pass`
on a pass, or one line per problem: an excerpt whose words are not in its
locator's stretch, a locator this kind does not take, a missing field, or more
excerpts than the share. Fix each line: re-copy the text from the snapshot,
correct the locator, fill the field, or drop the excerpt. Run the check again;
drop any excerpt you cannot make pass, since fewer excerpts always pass.

## Report

Reply with the check's pass line and nothing else. The run reads the
excerpts from the pack, not from your reply.

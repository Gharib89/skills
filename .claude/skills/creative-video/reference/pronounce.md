# Pronunciation

An English acronym or command name stays as written: the stage sends the
narrator its letters, so `aws s3 ls` is said "A W S" and not "oos". It matches
whole words without case or the punctuation around them (`API.` and `api`),
from a built-in list (`api`, `aws`, `cli`, `cpu`, `css`, `dns`, `html`, `http`,
`https`, `iam`, `npm`, `sdk`, `sql`, `ssh`, `url` and the like) with
`project/kit/pronounce.json` over it: one word to its spoken form, which
replaces the built-in one.

```json
{ "aws": "A W S", "kubectl": "cube control", "s3": "S 3" }
```

A key is one word (a space in it is refused before any voicing). The map
changes the voiced text and its cache key, so an edit re-voices only the scenes
whose words it names; `voice.json`, the captions and every gate keep the
written words, each with one time spanning its spoken letters. It applies to
English narration only: Egyptian Arabic QC already respells English terms.

In Egyptian Arabic narration, keep English terms in Latin letters (`pull
request`); QC spells them in Arabic letters as a speaker says them. An acronym
of more than four capitals QC reads as a word: write it as its letters' names
in Arabic.

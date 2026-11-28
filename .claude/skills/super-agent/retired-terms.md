# Retired terms

Words and file names super-agent stopped using, one row each: the super-agent
version that retired it, the word, and the word that replaces it (`None.` where
nothing does). `update-skills` plans every row inside the version range a
refresh crosses, replaces the word in the consumer repo's own documents and
renames a file whose name is the word. A PR that retires a word adds its row
here in the same diff. A cell holds no `|`.

| Version | Term | Replacement |
|---|---|---|
| 0.25.0 | launch brief | launch message |
| 0.25.0 | re-brief | step-in |
| 0.25.0 | brief.sh | None. |
| 0.25.0 | launch-brief.md | step-ins.md |
| 0.26.0 | briefed | scoped |
| 0.44.0 | notify.sh | wake-timer.sh |
| 0.46.0 | paused | owner-run |
| 0.46.0 | unpause | adopt |
| 0.46.0 | give back | Watch <thread> |
| 0.47.0 | pushed mark | alert mark |
| 0.47.0 | unpushed need | raised need |
| 0.47.0 | Needs you row | needs-you message |
| 0.51.0 | probe thread | None. |
| 0.51.0 | reply file | None. |
| 0.51.0 | reply.sh | owner-read.sh |

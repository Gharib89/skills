# The storyboard is an artifact page with a local fallback

`explainer-video` shows its storyboard as a private claude.ai artifact page: one card per scene, answers written to the page's database, and a Submit that wakes the run, the pattern `grill-with-artifact` already uses (ADR 0006). When the session has no artifact tools, the run writes `explainers/<slug>/storyboard.html` and the human pastes the page's answers text back into the terminal. A local Node server that takes the answers was rejected: a port to manage and no way to wake the session, for a skill whose other stages already run in a Claude Code session.

## Consequences

- The default path is local except for this page: the script, stills and narration of a run reach claude.ai when the artifact page is used.
- The style card uses the same page mechanism and the same fallback.
- Both surfaces read one storyboard document, so the run writes its answers contract once.

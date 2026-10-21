### Explainer video

**Explainer video**:
A narrated video, as long as the operator asks for (two minutes by default), that the `explainer-video` skill makes from one or more sources: repos, documents, URLs, or a topic researched on the web.
_Avoid_: promo, trailer, reel

**Part**:
One of the explainer videos a request longer than five minutes is split into, on the operator's yes: the parts share the brief, the source pack and the style profile, and each is delivered as its own video. A part stands alone: it opens with its own promise and closes with its own recap, and every part after the first bridges back to the one before.
_Avoid_: clip (that is the clip insert), episode, chapter (that is a section)

**Part plan**:
How a split request's content is divided between its parts: each part's title, focus, length and the excerpts it draws on. The skill proposes it with the offer to split, and the operator accepts or edits it before any part is scripted.
_Avoid_: series outline, episode list

**Section**:
A group of points inside one explainer video longer than five minutes, opened by a short scene of its own and marked so a player can jump to it. The video keeps one promise at the start and one recap at the end.
_Avoid_: chapter, part (that is its own video), segment

**Steering prompt**:
Free text given with a run that moves the brief off its defaults, such as a narrower focus, a longer cut or another style.
_Avoid_: flags, options, instructions

**Brief**:
One run's settings, one value per knob (focus, length, audience, language, style, voice, aspect), plus what the video must include and must avoid: the steering prompt laid over the defaults. The storyboard shows it, so a misread is caught before anything renders.
_Avoid_: config, settings, spec

**Source pack**:
Everything a run read, kept word for word, with the numbered excerpts its script may cite. A topic with no source gets a source pack too, from the pages researched for it, and the storyboard lists what the pack holds.
_Avoid_: context, corpus, research notes

**Excerpt**:
A passage quoted word for word from one source in the source pack, with where it was found (a file and line, a page, a section of a web page). A narration sentence that makes a claim cites the excerpts that support it.
_Avoid_: snippet, fact, citation

**Script**:
A run's scenes in order, each with its role in the video, its narration sentences and what is on screen. Every sentence that makes a claim cites its excerpts; a connective sentence (a transition, a framing question) is marked as making none. The storyboard is built from it.
_Avoid_: storyboard, outline, transcript

**Script gate**:
One of the automated checks the script must pass before it is voiced: the scene arc, each scene's spoken-character budget, every cite found word for word in the source pack, every sentence judged supported or connective by the support checker, the brief's must-include and avoid lists, and house rules. A support verdict still red after two fix attempts stops the run.
_Avoid_: lint, script check, video gate

**Kept term**:
A word an Arabic run leaves in English (a code name, a product name, an acronym), spoken, shown and captioned the same way everywhere in the video. The storyboard lists a run's kept terms, and the human can change them.
_Avoid_: glossary term, untranslated word, loanword

**Narrator**:
The voice that reads a run's narration, named by the brief's voice knob. Each language has a default female and male narrator; another is used only when the brief asks for it.
_Avoid_: speaker, TTS voice, voice-over

**Voice QC**:
The check each voiced scene must pass before the run uses its audio: the aligner's transcript is compared with the narration for content-word recall and precision, and the speaking rate must sit inside a band. A failing scene is not cached, so the next run voices it again. Once every scene passes, in a run with a brief, the voiced scenes and the render's closing hold must land within 10 percent of the brief's length, or no word timeline is written. A numeral in the narration costs precision, since the words it is spoken as match nothing in the text.
_Avoid_: TTS check, audio QA

**Own voice**:
A narrator that speaks in a real person's voice, made by converting a default narrator's render to a recorded clip of that person. It is used only when the brief names it, and only for a speaker whose consent is on record.
_Avoid_: clone, voice clone, custom voice

**Storyboard**:
A browser page with one card per scene (its narration, the scene in the run's style shown at its fullest moment and playing through its seam into the next, its timing and style notes) that the human approves or revises scene by scene, under an estimate of the first render's time. Each card arrives on the agent's recommendation (approve, or its proposed fix for a card with a finding), so the human may take the whole board in one answer. It is the one human checkpoint before production; everything after it runs behind video gates.
_Avoid_: outline, shot list, script

**Menu**:
A select on a storyboard card (its component, camera beat, emphasised item or seam) or on the brief (a menu knob), set to the agent's pick and listing only the options the board document gives it. A menu changed from the agent's pick turns its card to Revise and applies on Submit: the agent rebuilds the changed scenes and posts the next board version. A card menu steers a scene's component, camera, emphasis and seam; the agent still writes the scene's narration and content.
_Avoid_: dropdown, picker, preset

**Live build**:
A video's own composition played in the browser instead of rendered: it can be seeked to any moment, looped, or driven by the narration, so the human sees motion before anything renders. Storyboard cards, the animatic and the style card's frames are live builds.
_Avoid_: preview, mockup, prototype

**Animatic**:
The whole video's scenes and seams played in order, without a break, over the run's real narration, so the human judges pace and motion before the final render.
_Avoid_: preview, rough cut, slideshow

**Board version**:
One state of a run's storyboard, posted as one document the page renders: the first cards, each revision, a gate stop's banner with the failing cards reopened, and the delivered video's clips. A version is never rewritten once the human can see it; a change is the next version.
_Avoid_: round, board update

**Sampling pass**:
Layout and reading time judged on a composition's samples (the ones the video gates take) before any video exists, so a red shows on its storyboard card instead of after a render. Its reds are findings the human sees, not video gates: they open their cards on Revise and no gate attempt count tracks them.
_Avoid_: pre-gate, dry run

**Style profile**:
A saved, named look (a palette, type faces, a type scale and a visual grammar) that a run can use. One profile is the default; a profile can come from a prototype, screenshots, a website or a deck.
_Avoid_: theme, preset, template

**Visual grammar**:
The part of a style profile that holds for every scene of a video: how scenes hand over at a cut, how the camera moves, how type enters, the texture over the ground, the ease of every move, and its bans. A profile states only where its grammar departs from the default one. Each scene places it on its own narration and may reach past it wherever the grammar bans nothing.
_Avoid_: motion register, direction

**Type scale**:
The named text sizes of a style profile, from a display title down to a label. Every scene, a component or a custom scene, sizes its text from these steps and never states a size of its own.
_Avoid_: font sizes, type ramp

**Ban**:
A component or a technique (3D, blur, a camera move, per-word type, arrows drawn on) a style profile forbids in every scene of a video. A scene that uses one is refused, whether a component or its own custom scene draws it.
_Avoid_: restriction, disallowed effect

**Style card**:
A page showing a draft style profile rendered on sample frames (a title, a diagram, a caption, a code frame, an Arabic frame), with each colour marked as measured from the reference images, derived, or adjusted for contrast, each font a source decided marked as its own, the replacement for one it names, or an Arabic companion, and each visual grammar field marked as measured from a reference video, judged from its frames, or the default. The frames play the grammar's motion, and one seam hands a frame to the next. The human edits a colour or a font on the card itself, then saves the profile, uses it once, or asks for a revision.
_Avoid_: style preview, mood board

**Card version**:
One state of a style card, posted as one document the page renders: the first frames, and each rebuild after an edit or a revision. A version is never rewritten once the human can see it; a change is the next version.
_Avoid_: card round, card update

**Reference image**:
An image a draft style profile is drawn from: a screenshot, a slide, a video frame, or a page of a website as rendered. Its colours are measured; a video's frames around each cut also show its visual grammar. Every source of a style becomes reference images first; a colour the source declares counts only where its reference images show it.
_Avoid_: sample, screenshot (for the general case), mood image

**Colour candidate**:
A colour measured from a draft style profile's reference images, a surface ranked by its area or an accent among the saturated pixels, with its share and the images that show it. Claude assigns each colour token a colour candidate by its id, never a hex.
_Avoid_: candidate (that is `file-issue`'s open-issue match), swatch

**Composer**:
The one engine that lays out every scene of an explainer video on a single timeline, so captions, the score and word timing run unbroken from the first scene to the last.
_Avoid_: renderer, backend, framework

**Component**:
One kind of on-screen content a scene shows, drawn by the composer under the visual grammar: cards, a flow, a chart, kinetic type. A scene that names a component shows exactly that one, never one nested in another; a custom scene draws its own markup instead.
_Avoid_: visual, block, widget, template

**Rich component**:
A component that moves the frame itself past the visual grammar's camera: its own camera path, a moving ground, 3D, or kinetic type that moves word by word on the narration. Richness belongs to the component, never to one scene's use of it, and the storyboard marks every scene that shows one.
_Avoid_: heavy component, advanced visual

**Custom scene**:
A scene whose on-screen content the agent writes itself instead of taking a component, held by the same hard rules and video gates as every scene. The agent writes a **fragment**, an HTML file beside the scene file holding markup, plain style rules and a timeline script, and the scene names its `intent` and the **cues** the fragment reads by name. Compile holds every fragment to one lint and a rich scene is marked on its card. Components are tested shortcuts beside it, not a menu it must choose from.
_Avoid_: freeform scene, escape hatch, bespoke component

**Cue**:
The spoken moment a reveal, the camera beat or the emphasis lands on: a sentence of the scene's narration, or a word or phrase within that sentence.
_Avoid_: trigger, beat (for the general case), keyframe

**Clip insert**:
A pre-rendered video made outside the composer (a maths animation, a screen recording: footage the composer cannot draw from a seek) that fills one scene's slot on the composer's timeline.
_Avoid_: embed, sub-render, segment

**Score**:
The music and sound effects an explainer video carries under its narration, synthesised in code and arranged to the scene timings (the music, when the brief opts in, made by the ACE-Step model instead): the music ducks under speech, and sound effects mark the cuts and the end of the narration, never more in a minute than the sfx gate's floor. The same timings and seed give the same score, an ACE-Step one on the same device.
_Avoid_: soundtrack, background music, BGM

**Video gate**:
An automated check a run must pass after the storyboard is approved and before the video is delivered, such as layout, contrast, reading time, loudness, caption timing or sound effects per minute. Each has a floor the skill sets, and a style profile may only tighten every one but the critic's and the determinism gate's (which renders a frame of each scene twice and has no floor but equal pixels); a gate still failing after two fix attempts stops the run, and no video ships, while a red determinism gate stops at once, since no change to the script could clear it.
_Avoid_: QA, check, local gate

**Seam**:
How one scene hands over to the next at a cut, as the visual grammar names it (a zoom-through, a cut on a curve, a plain cut); a scene may pick another seam of the same family for its own hand-over. The outgoing scene draws it, running on past its own last moment while the next scene starts on time.
_Avoid_: transition (for the grammar's field), wipe

**Readable**:
A text box is readable at a moment when it is fully shown, outside a seam, and not being carried into or out of the frame by the camera. The layout and reading time gates judge a box only while it is readable.
_Avoid_: visible, settled, on screen

**Reading time**:
The video gate that every text box is readable, in one unbroken stretch, long enough for its words to be read. Kinetic type revealed word by word on the narration is read along with the voice instead, and must stay readable whole for a moment after its last word is spoken.
_Avoid_: dwell time, hold time

**Critic**:
An independent reviewer that reads a run's contact sheets, motion strips and seam strips: its hard failures (unreadable or invented content, a broken right-to-left layout) block like a video gate, and its scores and its worst defects only advise.
_Avoid_: judge, grader, reviewer

**Contact sheet**:
One image per scene of a rendered explainer video: four of its frames (its quarter marks and its fullest moment), cut from the encoded video and tiled two by two, that the critic reads in place of the video.
_Avoid_: snapshot, thumbnail, filmstrip

**Fullest moment**:
The moment of a scene at which the most words are readable at once, the latest such moment when several tie.
_Avoid_: end state, settled frame, key frame

**Motion strip**:
One image per moving scene of a rendered explainer video: 12 consecutive frames of it, starting 5 before its peak-motion frame outside its seams, cut from the encoded video and tiled six by two, that the critic reads beside the contact sheet to judge motion. A scene that hands over at a seam gets a second strip of that seam. A motion record next to them names the peak frame and the dead beats.
_Avoid_: filmstrip, flipbook

**Seam strip**:
One image per scene that hands over at a seam: 12 consecutive frames tiled six by two with that seam's window in the middle tiles, so the scene leaving and the one arriving show together, that the critic reads to judge the hand-over. None at a plain cut or for the last scene.
_Avoid_: transition strip

**Dead beat**:
A stretch of 1.5 s or more of a scene in which nothing moves but the camera's drift and the texture.
_Avoid_: still, pause, hold

**Tool cache**:
The per-user folder setup installs a run's tools into: the npm packages and Chrome under the lockfile's hash, each model and Python env under its pinned revisions, so copies of the skill at different versions coexist. An install no catalogue row lands in on this machine (npm or Chrome under another hash, a model or env at another revision or for the other device) that no run has used for 30 days is stale, and setup's install removes it.
_Avoid_: node_modules, tools folder

**Font store**:
The per-user folder of fonts fetched by family at a pinned version, OFL or Apache faces only, by setup (which also installs the `fonts` rows saved style profiles carry), or by a draft style profile for a family setup does not install; shared by every run and style profile.
_Avoid_: font cache, fonts folder

# Motion design references for explainer-video

Research for [#773](https://github.com/Gharib89/skills/issues/773) on the map
[#770](https://github.com/Gharib89/skills/issues/770). Date: 2026-10-17.
Builds on `research/explainer-design-refs` (#656: palettes, type, pacing of
five directions) and `research/explainer-effects` (#657: which libraries carry
which effect); facts settled there are not repeated. This file covers the
motion and camera grammar: what moves, how scenes hand over, how type behaves.

Labels: **measured** (a command was run, named inline), **documented** (a
primary source says so, linked or cited), **inferred** (my reading of the
measured frames or sources), **guess** (plausible, unproven).

## Answer

Narrated explainers and launch films move in two different ways, and the skill
should copy the first.

1. **Narrated explainers build, they do not cut.** The five narrated explainers
   cut between 0 and 10.2 times a minute, while the kinetic type and montage
   films cut 41 to 46 times a minute (measured, ffmpeg scene detection, table
   below). Kurzgesagt ran 454 s with no hard cut above the 0.3 threshold;
   ByteByteGo ran 320 s with none. The picture changes because a held frame
   gains parts as the narrator names them, a camera moves across one large
   canvas, or one shape becomes the next (measured, frame strips). This is the
   grammar that fixes "videos read as held slides" (#770 Notes): the frame may
   hold, but something on it must change on each spoken idea.
2. **The five top techniques for this skill**, in rank order: a diagram that
   builds on narration word marks; a highlight plus leader-line callout on a
   fixed object; a 2D camera that pushes into and pulls out of one large
   canvas; continuous transitions (shape wipe, morph, camera carry) in place of
   cuts; and a zoom-callout inset. All five are HTML plus GSAP, cost small or
   medium, and survive a right-to-left run with mirrored direction (inferred
   from the frames and the RTL probe below).
3. **Launch films add depth, not pace.** Linear, Figma and Raycast put real UI
   on a tilted plane with depth of field and slow drift; AMD and Applied
   Materials explode a product into layers and fly through it (measured,
   frames). The tilted plane is CSS; the exploded stack and fly-through are
   Three.js work (inferred).
4. **Arabic breaks only at the letter.** In Chrome 155, word spans under
   transforms, SVG `textPath`, a tilted CSS 3D plane and a right-anchored
   highlight all keep Arabic joined; per-letter `inline-block` spans (what a
   character split produces) break every join, and `letter-spacing` is
   ignored on Arabic (measured, `google-chrome --headless --screenshot` of
   the probe page in [Arabic RTL probe](#arabic-rtl-probe)). So every
   letter-level kinetic move in the references is Latin-only; the map's
   "whole words, never letters" rule is the right line.
5. **Pace**: narration runs 148 to 214 words a minute in the explainers and
   125 in Apple's presenter film (measured, captions over duration). Fireship
   is the fast outlier at 214 and still cuts only 4.7 times a minute.

## Method

All videos were downloaded once at up to 720p into a scratch folder and
deleted after analysis. No frames are committed, since this repo is public and
the stills belong to other companies; each observation below links the video
at the timestamp it describes, with my own written description of the frame.

- Download: `yt-dlp -f "bv*[height<=720]" --write-info-json --write-auto-subs`.
- Hard cuts: `ffmpeg -vf "scale=320:-2,select='gt(scene,0.3)',showinfo"`, count
  of `pts_time` lines.
- Change events and still share: per-frame `lavfi.scene_score` at 10 fps
  (`fps=10,select='gte(scene,0)',metadata=print`); "change" is a score of 0.1 or
  more, "still" is under 0.002.
- Words a minute: words in the English caption track, rolling auto-caption
  repeats removed, over the full duration (intros and outros included, so
  these slightly undercount speech rate).
- Frames: a 16-frame contact sheet per video, then 12-frame strips at 0.25 to
  2 s steps around chosen moments, read one by one.

Caveat (measured): the scene score under-reads slow motion on dark,
low-contrast grounds. Linear's camera drifts in every strip frame, yet 85 % of
its 0.1 s steps score as still. Read the still column as "how much of the
frame changes", not "whether the camera moves".

| Family | Video | Dur s | Hard cuts/min | Changes/min | Still % | Words/min |
|---|---|---|---|---|---|---|
| Launch | [Apple, The new iPad Pro + M4 chip](https://www.youtube.com/watch?v=zXJbdtxh0XE) (2024) | 241 | 6.5 | 8.5 | 66 | 125 |
| Launch | [Linear, Introducing Linear Agent](https://www.youtube.com/watch?v=mRql2VJ99gM) (2026) | 55 | 0 | 4.4 | 85 | none |
| Launch | [Raycast, New Raycast. Coming 2026](https://www.youtube.com/watch?v=Mi173xGb0ZA) (2025) | 39 | 7.8 | 14.0 | 58 | none |
| Launch | [Figma, All the launches at Config 2025](https://www.youtube.com/watch?v=NHodnYFUT_I) | 81 | 68.1 | 98.4 | 17 | none |
| Explainer | [Kurzgesagt, Tiny Bombs in your Blood](https://www.youtube.com/watch?v=BSypUV6QUNw) (2019) | 454 | 0 | 14.7 | 51 | 156 |
| Explainer | [3Blue1Brown, Large Language Models explained briefly](https://www.youtube.com/watch?v=LPZh9BOjkQs) (2024) | 477 | 0.8 | 2.3 | 69 | 165 |
| Explainer | [Fireship, Docker in 100 Seconds](https://www.youtube.com/watch?v=Gjnup-PuquQ) (2020) | 126 | 4.7 | 16.6 | 85 | 214 |
| Explainer | [ByteByteGo, What happens when you type a URL](https://www.youtube.com/watch?v=AlkDbnbv7dk) (2022) | 320 | 0 | 0.0 | 89 | 148 |
| Explainer | [Vox, Why this black hole photo is such a big deal](https://www.youtube.com/watch?v=pAoEHR4aW8I) (2019) | 388 | 10.2 | 15.0 | 46 | 163 |
| Kinetic type | [Apple, Don't Blink](https://www.youtube.com/watch?v=jk6sz25OZgw) (2016, re-upload) | 119 | 40.9 | 56.1 | 44 | none |
| Kinetic type | [Keo, Hozier Eat Your Young kinetic type](https://www.youtube.com/watch?v=bVXATN0Qh-I) (2024) | 72 | 6.6 | 47.4 | 27 | none |
| Kinetic type | [Optious, Kinetic Typography Brand Video](https://www.youtube.com/watch?v=TDC7eVrkduY) (2025) | 36 | 46.1 | 118.7 | 25 | none |
| 3D | [Branch Education, How do SSDs Work, 3 min](https://www.youtube.com/watch?v=E7Up7VuFd8A) (2020) | 174 | 0.3 | 9.3 | 41 | 154 |
| 3D | [AMD, 3D V-Cache Technology](https://www.youtube.com/watch?v=ymfEB4MwrO0) (2022) | 70 | 8.5 | 14.5 | 36 | none |
| 3D | [Applied Materials, The World of Advanced Packaging](https://www.youtube.com/watch?v=-egYoxajTz0) (2021) | 71 | 1.7 | 9.3 | 26 | none |

"none" means music only, or captions not fetched. Figma's 92 cuts in 81 s are
the scene detector's count (measured, `cuts.txt`).

Downloaded and dropped, because their grammar is camera footage the skill
cannot build: Stripe Sessions 2024 (event recap, 45.7 cuts/min), NVIDIA
Blackwell: The Journey From Die to Data Center (factory footage, 19.6
cuts/min), Google, Welcome to the Gemini era (live action between UI shots)
(measured, contact sheets).

## What each reference does

Frame times are seconds into the video. Every bullet is **measured** from the
named frames unless it says otherwise.

### Product launch films

**Apple, iPad Pro + M4** ([callout, 0:53](https://youtu.be/zXJbdtxh0XE?t=53),
[bento, 3:35](https://youtu.be/zXJbdtxh0XE?t=215))

- Camera: locked-off presenter in a deep set; graphics are full-frame cut-ins.
- Transition: hard cut to a flat die diagram on black (51.5 s), back by hard cut.
- Signature move: as the presenter names "4 performance cores" the matching
  die region fills white, the die slides right, and a leader line draws out to
  a label whose bullet lines brighten one by one, dim to bright (52 to 55 s).
- Type: small sans labels, a hairline rule under each heading, grey sub-bullets.
- Recap: a bento grid of 12 tiles (120GB/s, 50 %, 4x, 3 nm) held about 7 s
  before the cut back (212 to 219 s).
- Pacing: 125 words/min, 6.5 cuts/min; graphics last as long as the sentence.

**Linear, Introducing Linear Agent** ([tilted plane, 0:09](https://youtu.be/mRql2VJ99gM?t=9),
[end card, 0:46](https://youtu.be/mRql2VJ99gM?t=46))

- Camera: the whole app UI lies on a plane tilted back and rotated (roughly
  rotateX 35 to 45 deg, rotateZ -10 to -15 deg, inferred), and the camera
  slowly trucks and pushes along it for 45 s with no cut.
- Depth: strong depth of field; the near edge is sharp, the far edge blurs
  into black.
- Transition: dip to black between UI regions (3.5 s), then the plane returns
  framed on the next region.
- Type: UI text typed character by character into the prompt field; end card
  "Linear" resolves from a heavy blur with a gradient sheen (45.4 to 47 s),
  then "At your command." fades in beside it.
- Colour: near-monochrome grey on black; colour only in status icons.

**Raycast, New Raycast. Coming 2026** ([macro crop, 0:02](https://youtu.be/Mi173xGb0ZA?t=2),
[title card, 0:30](https://youtu.be/Mi173xGb0ZA?t=30))

- Camera: macro crop, the search bar fills the frame and bleeds off the right
  edge, then slides left across 1 s; later shots pull back to the whole panel.
- Texture: a blurred black-and-white silk surface behind every UI shot.
- Type: typed query ("cl", "clipbo", "clipboard") with live results.
- End sequence: tiny monospace caps on black, "NEW" fixed left and the second
  word swapped every 0.67 s (LAUNCHER DESIGN, COMPACT MODE, HOTKEY RECORDER,
  VOICE FEATURES, AI CHAT, CLOUD SYNC ENGINE), then the two words slide
  together into "NEW RAYCAST" (28 to 34 s).

**Figma, Config 2025 launches** ([split word grid, 0:03](https://youtu.be/NHodnYFUT_I?t=3),
[card fan, 0:07](https://youtu.be/NHodnYFUT_I?t=7),
[type on path, 0:42](https://youtu.be/NHodnYFUT_I?t=42))

- Opening: the word "Figma" becomes its "F", which builds into a collage of
  coloured blocks with selection handles (0.5 to 2.5 s).
- Type: product names split across a four-column frame grid ("Fig / ma",
  "Sit / es") at 3.5 s; text set on a curved path with Bezier handles (42 s).
- Depth: website cards fanned in perspective, stacked in depth (7.5 s).
- Camera: a cursor is the protagonist; it drags, resizes and edits, and the
  frame follows it (resize across breakpoints, 8.5 to 11.5 s).
- Texture: grain and progressive blur demonstrated as sliders (46 to 53 s).
- Pacing: the fastest launch film (98 changes/min); a montage, not a story.

### Tech explainers

**Kurzgesagt, Tiny Bombs in your Blood** ([counter, 0:40](https://youtu.be/BSypUV6QUNw?t=40),
[blob wipe, 2:31](https://youtu.be/BSypUV6QUNw?t=151),
[overview, 2:35](https://youtu.be/BSypUV6QUNw?t=155))

- Camera: continuous. A push-in on a blood vessel while a white ring marks one
  protein and a pink pill counter types out "15,000,000,000,000,000,000" digit
  group by digit group (38 to 41 s).
- Transitions: no hard cut in 454 s (measured, scene detection). Scenes hand
  over by organic shape wipes (bubbles grow to fill the frame, 150 to 152 s),
  by a large circle iris that becomes the next scene's subject (160 s), and by
  camera carry.
- Signature move: a full pathway map builds row by row on navy (152 to 157 s),
  then the camera zooms into one row and the rest falls away (158 s). The
  overview map returns at the end (440 s) as the recap.
- Labels: rounded pills in saturated colours, bold sans, attached to their
  object; idle motion on every character (bobbing, drifting proteins).
- Colour: each scene has one ground hue (cyan, violet, navy), characters in
  hot accents.

**3Blue1Brown, LLMs explained briefly** ([into the box, 0:36](https://youtu.be/LPZh9BOjkQs?t=36),
[magnifier, 2:02](https://youtu.be/LPZh9BOjkQs?t=122),
[scale reveal, 2:15](https://youtu.be/LPZh9BOjkQs?t=135))

- Camera: mostly locked on black, with a few 3D moves: the "model" box turns
  translucent as the camera passes into it, revealing a lattice of dials
  (36 to 38 s), and later a long fly-over of a huge 3D grid of dials shows
  scale (132 to 138 s), then pulls back to the box.
- Signature move: a magnifier inset; a square on one dial connects by two
  lines to an enlarged copy above the box, and the dial turns while a bar
  chart of next-word probabilities updates live (120 to 128 s).
- Type: serif (LaTeX style) set on the frame; key words in yellow; a title
  morphs word by word ("Parameter / Weight" to "Large" to "Large Language
  Model", 120 to 131 s); predicted words drop out of the box under an arrow.
- Pacing: 165 words/min against 0.8 cuts/min and 69 % still: the frame holds
  while one element changes.

**Fireship, Docker in 100 Seconds** ([stack and label, 0:40](https://youtu.be/Gjnup-PuquQ?t=40))

- Camera: none; a centred stack diagram on a dark starfield.
- Build: layers stack bottom up (Hardware, Operating System, then Docker
  Engine, then App 1 and App 2) as each is named (28 to 40 s).
- Signature move: a meme or stock clip plays inside a diagram slot (a cat
  squeezing through a door as the "virtual machine", a running cheetah as
  containers), then the slot returns to the diagram.
- Type: heavy all-caps condensed sans for the punchline ("SHARED KERNEL") with
  an emoji pointer; code panels in an editor frame with the keyword in colour
  ("FROM", "RUN", "CMD") echoed in a title above it.
- Pacing: 214 words/min, the fastest narration, yet 85 % still frames:
  speed comes from the voice and many small additions, not from cuts.

**ByteByteGo, What happens when you type a URL** ([whiteboard, 3:50](https://youtu.be/AlkDbnbv7dk?t=230))

- Camera: one white canvas for the whole video; zooms into a sub-diagram
  (URL components) and back out to the growing whole.
- Build: numbered steps added one at a time (1 Bob enters a URL, 2 cache,
  3 DNS, 4 TCP, 5 HTTP); nothing leaves the canvas.
- Highlight: the URL's parts are colour-coded, and a highlight cycles over
  "http" while the narrator explains the scheme, held about 16 s (38 to 56 s).
- Constant chrome: title bar and a presenter picture-in-picture.
- Pacing: 0 change events at 0.1 per minute: the most static reference. It
  is close to what the skill makes today (inferred), and still works because
  each sentence adds or lights one part.

**Vox, Why this black hole photo is such a big deal** ([pill labels, 2:06](https://youtu.be/pAoEHR4aW8I?t=126),
[zoom callout, 2:10](https://youtu.be/pAoEHR4aW8I?t=130),
[compare wipe, 2:18](https://youtu.be/pAoEHR4aW8I?t=138))

- Evidence first: NASA footage and photos, labelled with magenta pills on
  leader lines ("EVENT HORIZON", "ACCRETION DISK").
- Signature move: a spectrum bar with a trapezoid zoom-callout expanding the
  thin "visible to humans" slice into a rainbow strip (128 to 134 s).
- Transition: a vertical line wipes a telescope photo into its X-ray image,
  a before-and-after reveal (138 s); elsewhere hard cuts on sentences.
- Texture: dark ground with film grain and a faint vignette.
- Colour: one accent (magenta) for every annotation, across the video.

### Kinetic typography

**Apple, Don't Blink** ([word dissolve, 0:23](https://youtu.be/jk6sz25OZgw?t=23),
[polarity flip, 0:25](https://youtu.be/jk6sz25OZgw?t=25))

- One to three words at a time, centred, in a heavy grotesque.
- The ground flips black, white, black on alternate words (24 to 26 s).
- Words accumulate ("Two", "Two new", "Two new blacks.") or replace each
  other with a quick per-letter dissolve ("This" to "is", 23 s), over a product
  shot that slowly rotates.
- Scale is the emphasis: "7" fills the frame, then "Siete".
- Pacing: 40.9 cuts/min; it is a trailer, tied to music, not to narration.

**Keo, Hozier Eat Your Young** ([type on path, 0:20](https://youtu.be/bVXATN0Qh-I?t=20),
[word as scenery, 0:13](https://youtu.be/bVXATN0Qh-I?t=13))

- Words are the set: "WORLD" sits in a city skyline; "RACE" is a track a
  silhouette runs on; a hand carves "CARVIN'" letter by letter.
- Letters ride a wave path that scrolls ("WANNA SMELL THE DINNER COOKIN'",
  19 to 21 s).
- Fast entrances carry heavy directional motion blur (15.75 s).
- Colour and texture: red, cream and black only, on paper grain, hand-cut
  rough display type.

**Optious, Kinetic Typography Brand Video** ([inline icon, 0:05](https://youtu.be/TDC7eVrkduY?t=5),
[hero word, 0:13](https://youtu.be/TDC7eVrkduY?t=13))

- An icon stands in for a word inside the sentence ("Since [bomb] the").
- Letters bounce in at offset baselines ("beginning", 8.5 s).
- A 3D object (a whale, a hair dryer) sweeps across the frame and pushes the
  words out: an occluding object as the transition.
- Hero word overflows the frame ("AWESOME"), and grounds flip black and white.
- Pacing: 118.7 changes/min, the busiest reference.

### 3D motion

**Branch Education, How do SSDs Work** ([cutaway, 0:47](https://youtu.be/E7Up7VuFd8A?t=47))

- Camera: a slow orbit to a frontal cutaway, then held (39 to 61 s).
- Signature move: a section view of one memory cell; electron particles pour
  into the charge-trap layers while a binary value beside it counts up
  (000 to 111).
- Labels: large coloured text placed in the scene ("Charge trap flash",
  "Electron level"), not in a caption band.
- Scale: pull-backs from one cell to 40,000 columns and 100 layers, with the
  numbers as giant labels (92 s).

**AMD, 3D V-Cache Technology** ([exploded macro, 0:52](https://youtu.be/ymfEB4MwrO0?t=52))

- Camera: macro product shots with very shallow depth of field, slow slides
  across the package.
- Signature move: the cache die lifts off the compute die, a lit gap between
  layers, iridescent silicon (49 to 56 s); "How it works" fades in over the
  product before it.
- Type: white captions, lower left, one line each.

**Applied Materials, The World of Advanced Packaging** ([fly-through, 0:13](https://youtu.be/-egYoxajTz0?t=13))

- Camera: one continuous dolly from a wide shot of the whole package into
  its layers (substrate, bumps, through-silicon vias, redistribution layer)
  and back out; 2 cuts in 71 s.
- Labels: placed in world space, so they scale and pass the camera as it
  flies ("Through Silicon Via (TSV)", 13 to 15 s).
- Bookend: the same wide shot opens and closes the film (2 s, 64 to 68 s).

## Patterns that fit a narrated explainer

- **Change per idea, not per second** (measured, table): the explainers hold
  46 to 89 % of 0.1 s steps still yet stay legible and lively, because each
  sentence adds, lights or moves one thing. Launch and kinetic films change
  50 to 120 times a minute because music, not speech, sets the clock.
- **One canvas, many views** (Kurzgesagt, ByteByteGo, 3Blue1Brown): build a
  large map once, zoom into the part being spoken about, pull back to the map
  as the recap. This turns a sequence of slides into one place (inferred).
- **The annotation layer is a system**: Vox's magenta pills, Kurzgesagt's
  coloured pills, Apple's hairline callouts, Branch's in-scene labels. Each
  keeps one label style across the video and attaches it to the object, not
  to a caption band (measured, frames).
- **Hand-overs carry something across**: a shape, a colour field, a camera
  path or an object survives the transition (Kurzgesagt iris, Optious
  occluder, Applied Materials dolly). Hard cuts are reserved for change of
  register: presenter to graphic in Apple, footage to diagram in Vox
  (measured, frames).
- **Recap shows the whole**: Apple's bento, Kurzgesagt's returning pathway
  map, Applied Materials' bookend shot (measured, frames).

## Arabic RTL probe

Probe: one HTML page, one row per case, rendered by
`google-chrome --headless=new --disable-gpu --window-size=1280,900
--screenshot` (Chrome 155.0.8059.84) with IBM Plex Sans Arabic at 40 px bold,
and the screenshot read by eye (measured). The rows, abridged:

```html
<div dir="rtl"><span style="display:inline-block;transform:scale(1.2)">تشارك</span> ...</div>  <!-- word spans -->
<div dir="rtl"><span style="display:inline-block">ا</span><span style="display:inline-block">ل</span>...</div>  <!-- letter spans -->
<div dir="rtl"><span style="color:#f5f3ec">ال</span><span style="color:#8fae6b">حا</span>...</div>  <!-- inline letters -->
<svg><path id="p" d="M20,90 C200,0 450,140 680,40"/><text><textPath href="#p" startOffset="50%" text-anchor="middle">الحاوية تشارك نواة النظام</textPath></text></svg>
<div style="perspective:900px"><div style="transform:rotateX(35deg) rotateZ(-8deg)">ابحث عن المشكلات <bdi dir="ltr">Docker Engine</bdi></div></div>
<span style="background:linear-gradient(#dc7a5a,#dc7a5a) right/60% 100% no-repeat">نواة النظام</span>
<div dir="rtl" style="letter-spacing:4px">الحاوية تشارك</div>
```

| Case | Result |
|---|---|
| Word spans, each `inline-block` with its own transform and opacity | joins kept inside every word; words must keep a real space or gap between spans |
| Letter spans, `inline-block` (what a character split makes) | every join broken: the word renders as isolated letters |
| Letter spans, plain `display: inline`, coloured | joins kept, so per-letter colour is safe, per-letter transform is not |
| SVG `textPath` on a gentle curve | joined and in right-to-left order |
| Text on a CSS 3D tilted plane, English term in `<bdi dir="ltr">` | joined; the Latin term sits at the line's left end, as RTL order wants |
| Highlight background anchored right, 60 % width | covers the first 60 % of the reading direction, as a sweep should |
| `letter-spacing: 4px` | no visible tracking on Arabic; a tracking animation is a no-op |

The probe used system Chrome, not the `chrome-headless-shell` HyperFrames
pins; the same Blink shaping is likely but unproven there (guess). GSAP
SplitText's character mode is the inline-block case (inferred from its
documented behaviour of wrapping each character in a `div`).

## Ranked technique catalog

Ranked by fit for a narrated technical explainer (does it tie motion to a
spoken idea), then cost, then RTL safety. Cost: **S** is a GSAP timeline over
DOM or SVG, an afternoon; **M** needs layout logic, an SVG plugin or a mask,
a day or two; **L** is a Three.js scene through the HyperFrames adapter;
**XL** needs bespoke illustration or modelling per video. Costs are inferred
from the frames and from #657 and #774 (HyperFrames runs GSAP by default and
Three.js through a frame adapter; its CSS `perspective` is projected
rectangles, not a camera; closed-form Three.js scenes are seek-safe). RTL
verdicts cite the probe where measured; the rest are inferred.

| # | Technique | Used by | Build | Cost | RTL |
|---|---|---|---|---|---|
| 1 | **Narration-locked build-up**: a diagram gains one part per sentence, nothing leaves until the recap | ByteByteGo, Fireship, Kurzgesagt pathway, Apple M4 | GSAP timeline keyed to word marks; parts are DOM or SVG nodes with staged opacity and transform | S | Survives: mirror flow direction (stack and rows stay, arrows and step order run right to left) |
| 2 | **Highlight plus leader-line callout** on a fixed object: region fills, line draws, label lines brighten in turn | Apple M4, Vox pills, ByteByteGo highlight, 3Blue1Brown yellow terms | SVG `stroke-dashoffset` line draw, fill tween, staggered label lines | S | Survives: callouts go to the mirrored side; a highlight sweep anchors right (measured) |
| 3 | **2D camera on one large canvas**: push in to the spoken part, pull back to the whole | Kurzgesagt, ByteByteGo, 3Blue1Brown, Branch pull-backs | A world `div` tweened by `scale` and `translate`; vector content so zoom stays sharp | S to M | Survives: camera path mirrors with the layout |
| 4 | **Continuous hand-over** instead of a cut: shape wipe, iris that becomes the next subject, occluding object, camera carry | Kurzgesagt (0 cuts in 454 s), Applied Materials, Optious, Linear dip to black | `clip-path` circle or blob tweens, or HyperFrames shader transitions (`sdf-iris`, `domain-warp`, per #657) | M | Survives: mirror any horizontal wipe direction |
| 5 | **Zoom-callout inset**: a frame on a detail connects by lines to an enlarged copy | 3Blue1Brown magnifier, Vox spectrum trapezoid | Cloned node at scale plus two SVG connector lines or a trapezoid | M | Survives: inset goes to the mirrored side |
| 6 | **Count-up in a label pill**: a number tweens or types out by digit group | Kurzgesagt quintillion, Apple stat tiles, Branch binary counter | GSAP number tween with `snap`, `Intl.NumberFormat` | S | Survives: digits stay LTR inside an isolated run (#656) |
| 7 | **Word-level kinetic headline** timed to speech: words replace or accumulate one beat at a time, scale is emphasis | Don't Blink, Optious, 3Blue1Brown title morph, Raycast word swap | Word spans with GSAP stagger on word marks | S | Survives at word level (measured); never split to characters (measured breakage) |
| 8 | **Real UI on a tilted plane** with depth of field and slow drift | Linear, Figma card fan, Raycast macro crop | CSS `perspective` with `rotateX` and `rotateZ` on a UI screenshot or live HTML; blur by a masked, blurred copy | M | Survives: Arabic joins on the plane (measured); mirror the tilt. Large `filter: blur` layers may slow headless capture (inferred from #657) |
| 9 | **Exploded stack**: layers separate along depth to show structure, then close | AMD, Applied Materials, Fireship (2D), 3Blue1Brown box | CSS 3D `translateZ` per layer for flat layers (M); Three.js group with closed-form offsets for lit solids (L, #774) | M or L | Neutral: labels sit outside the stack |
| 10 | **Recap whole**: bento grid of the key numbers, or a return to the opening map | Apple M4 bento, Kurzgesagt map, Applied Materials bookend | CSS grid with staggered reveal; or re-use technique 3 pulled fully back | S | Survives: `direction: rtl` mirrors the grid (inferred) |
| 11 | **Annotation system**: one pill or label style, attached to objects, for the whole video | Vox, Kurzgesagt, Branch | A style-profile token set plus an attach-to-node helper | S | Survives: pill text is a word run; leader lines mirror |
| 12 | **Cutaway with flowing particles**: a section view where small dots move along the process | Branch electrons, Kurzgesagt proteins | SVG or canvas dots on paths, positions from a seeded function of time | M | Mirror the flow if it denotes sequence; determinism needs a seeded RNG (inferred) |
| 13 | **Texture layer**: grain, blurred abstract backdrop, starfield, idle drift | Vox grain, Hozier paper, Raycast silk, Fireship stars, Kurzgesagt idle motion | A static noise PNG or SVG `feTurbulence` with a fixed seed; slow transform drift | S | Neutral |
| 14 | **Cursor-driven UI demo**: a cursor clicks, drags and types; typed text appears in a field | Figma, Raycast, Linear | SVG cursor on a GSAP path; text revealed by substring | M | Survives if Arabic types by word, since a substring re-shapes as it grows (inferred); the cursor icon is not mirrored (Material, via #656) |
| 15 | **Clip in a diagram slot**: a short video or image plays inside a box of the diagram | Fireship memes, Vox footage | HyperFrames `<video>` element in the slot | S | Neutral; clip licensing is the cost |
| 16 | **Text on a path** | Hozier wave, Figma curved type | SVG `textPath`, tween `startOffset` | S to M | Survives on gentle curves (measured joined); tight curves untested |
| 17 | **Blur-in resolve** for a title or end card | Linear end card, Hozier motion blur | `filter: blur()` and opacity tween | S | Survives (whole-word blur) |
| 18 | **Polarity flip and beat cut**: ground alternates black and white per word | Don't Blink, Optious | Class swap per word mark | S | Neutral; tires fast in a narrated piece over a minute (inferred from pacing) |
| 19 | **3D fly-through with world-space labels** | Applied Materials, 3Blue1Brown into the box | Three.js camera on a spline; labels as HTML projected from 3D positions so Blink shapes them | L | Survives with HTML labels (inferred); Arabic in a WebGL text mesh is unproven (guess) |
| 20 | **Scale reveal**: fly over thousands of repeated units | 3Blue1Brown dial grid, Branch 40,000 columns | Three.js `InstancedMesh`, closed-form camera (#774: 12,000 to 60,000 instances are published cases) | L | Neutral |
| 21 | **Word as scenery**: words become set pieces, figures interact with them | Hozier skyline and runner, Optious occluders | Bespoke illustration per scene | XL | Possible with whole Arabic words, but every scene is hand-made |
| 22 | **Letter-level kinetics**: per-letter bounce, carve, dissolve, tracking | Optious "beginning", Hozier carving, Don't Blink dissolve | SplitText characters | S | **Fails**: character spans break joins and tracking is ignored (measured). Latin-only, so out under the map's rule |

## Thin

- Each family has three to five references; one video per studio cannot
  separate a studio's habits from that video's choices.
- Scene-score metrics under-read slow motion on dark grounds (Linear) and
  over-read busy footage; cut counts above 0.3 can miss soft dissolves.
- Words a minute come from caption tracks, auto-generated for most, over the
  full duration; music-only videos have no figure.
- Apple, Don't Blink is a third-party re-upload; the frames match the
  campaign, but the source is not Apple's channel.
- Rotation angles and easing curves are read from frames, not measured from
  the source projects.
- The RTL probe ran in system Chrome 155, not the HyperFrames headless shell,
  and covered one Arabic face; tight-curve `textPath` and WebGL Arabic text
  were not probed.
- Costs are estimates against the references; none of the 22 techniques was
  built or rendered here. Render time per technique on the RTX 2070 is a
  prototype ticket's measurement.

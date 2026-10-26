# SPEC - "The Pass" (why agentic engineering)

## Concept and why
A restaurant kitchen on a Friday-night service, shot by one overhead cooking-show camera that never leaves the kitchen. The tickets are software tasks, the line cooks are AI agents, and the viewer is working their first night at **the pass**: the counter where every plate is checked before it goes out. A rookie (Sam, day 1) carries the wrong idea.

Picked over the game show and the nature documentary (`STORYLINES.md`) because the kitchen's pass *is* the mechanism: ticket → cook with tools → plate → probe → send back with a note, or serve. That is the agent loop as Anthropic describes it ("LLMs using tools based on environmental feedback in a loop"), so every striking picture in the film is also a step of the explanation. The audience device is the call at the pass: twice the viewer is asked to call it before the answer.

GOAL: the viewer leaves believing "agents do the cooking; my job is building the check every plate must pass, because I can't feel whether it worked."
OUTPUT: HyperFrames, 1920 × 1080, 30 fps.
TIME: 132.5 s × 30 = 3975 frames. No music, so no BPM: the voice is the clock.

## The wrong idea, on screen
Sam: "If the agents do the cooking, what's the chef for? Just send it all out!" It is staged as plates streaming off the pass with their cloches still on, then broken by the METR result printed as ticket strips whose **length is time**: the FELT strip (−20 %) is red and gets crumpled onto the spike.

## Questions held for a guess
1. t = 39.4–44.0 s: "Faster, or slower? Make your call." Two tape labels, FASTER / SLOWER, and the amber kitchen timer ticks for 2.6 s before the answer.
2. t = 87.1–89.5 s: "Will it pass?" The probe is in the plate, the timer ticks, the LCD rolls digits for 2.3 s.

## Where the metaphor breaks (said, t = 102–109 s)
"A probe reads one spot. A test checks only what you wrote down. So you still read the plate." On screen: the probe reads green in one spot while an un-probed corner of the same plate is wrong.

## Facts (each traced; see SOURCES.md)
- Vibe coding named by Andrej Karpathy, 2 Feb 2025; "I 'Accept All' always, I don't read the diffs anymore"; "not too bad for throwaway weekend projects".
- METR RCT, early 2025: 16 experienced open-source developers, 246 real issues, AI allowed at random on half; 19 % longer with AI; forecast −24 %, believed afterwards −20 %.
- METR, March 2025: the 50 % time horizon of frontier agents doubled about every 7 months over 6 years.
- Anthropic, "Building effective agents": agents are LLMs using tools based on environmental feedback in a loop; ground truth from the environment at each step; stopping conditions such as a maximum number of iterations.
- JavaScript: `0.1 + 0.1 + 0.1` evaluates to `0.30000000000000004` (checked with node in this session).
- Karpathy, Feb 2026: "agentic engineering": "you are not writing the code directly 99% of the time, you are orchestrating agents who do and acting as oversight"; "engineering" because "there is an art & science and expertise to it".
- Illustrative, marked on screen: the ticket lengths in the doubling shot (only the ×2 per ~7 months ratio is METR's), the cart example, "3 tries".

## LOOK - the rules of one medium: a working kitchen seen from above
Ground is never a void: every frame is steel, tile, iron or paper.

| Hex | Part | Meaning in the story |
| --- | --- | --- |
| `#B7BEC2` | brushed stainless (the pass), 1 px lines every 3 px at 7 % white | the stage; neutral |
| `#848C91` / `#DDE2E4` | steel edge shadow / bevel highlight | depth only |
| `#2B2D30` | cast-iron range and grates | where agents work |
| `#CDD1CF` + `#BFC4C2` grid 120 px | floor tile | between line and pass |
| `#FBFAF6` + `#24272B` | thermal ticket paper and its ink | what was asked: a task, a spec, or a printed fact |
| `#E6D7A3` + `#1D1D1F` | masking-tape label and marker | the chef's voice: names and rules the viewer should keep |
| `#CF3A2B` | red | failed against ground truth, or a belief that the facts break (FELT strip, FASTER, fail readout, send-back path) |
| `#2E8B4E` | green | passed against ground truth (probe reads right, plate served) |
| `#EFA00B` | amber | time: the kitchen timer, ticket strips whose length is time, the doubling |
| `#C27F00` | amber ink | amber when it is *text* on ticket paper (×2, months): #EFA00B on paper is 2.1:1, this is 3.2:1 (added after `check`) |
| `#E2CE86` | floor-marking tape | a spot someone should stand or a plate should stop (CHEF, YOU, the pass spot); replaced dashed black outlines after the fresh-eyes review |
| `#FAFAF8` | chef whites | the cooks (agents) and Sam |

Accent ration: red, green and amber never appear without their meaning; at most one of them is the focus of a frame.

Type (two faces, both from the kitchen):
- Ticket print: IBM Plex Mono 500/700 (bundled). Ticket body 30 px, ticket headline 40–56 px, big ticket numbers 120–180 px. Exemption from the BANNED "small monospace caps labels": thermal receipt print *is* the medium of a ticket; it is never used as decoration and never under 30 px.
- Marker on tape: Permanent Marker (Apache 2.0, `assets/fonts/PermanentMarker.woff2`), 48–150 px, tracking 0, tape rotated −3° to +2°.

Light and depth: one key from the top-left. Objects on steel cast `0 8px 14px rgba(20,24,28,0.28)`; paper `0 4px 8px rgba(20,24,28,0.22)`. Grain 2 % on steel. No vignette, no glow, no bloom.

OBJECTS (each drawn so it reads without a label):
- Ticket: thermal paper strip 300–420 px wide, torn zig-zag bottom edge, a clip bar.
- Printer: matte black box `#25282B` with a paper slot, the ticket emerging from it.
- Ticket rail: a steel bar with the tickets hanging from it.
- Plate: white disc with a raised rim ring, contact shadow. Cloche: steel dome, off-centre specular highlight.
- Cook from above: toque disc with radial pleats + shoulder ellipse + two arms to the pan handle; tape name on the shoulders.
- Range: iron band with four grates (concentric rings and cross bars), a pan on each.
- Probe thermometer: dark body `#34383C`, LCD `#C9D3B8` with digits `#1E241B`, steel needle.
- Kitchen timer: amber dial, white face, an ink `#24272B` pointer (red is reserved for failure).
- Order spike: a steel spike on a round base, where done or discarded tickets go.

## MOTION
- Event rate: 12–18 picture changes a minute minimum, timed to the word that names them (cue table in `tools/timing.json`); peaks of 3–4 changes in a sentence that names several things.
- Eases by role: arrival `expo.out` 0.5–0.7 s; paper printing `none` (linear: a printer feeds at constant speed, 0.6 s per 100 px); camera `power2.inOut` 0.9–1.4 s; thrown/slid objects `power3.out` with 0.15 s settle; exits `power3.in` at 60 % of the entrance.
- Tape lands with a press: scale 1.06 → 1, rotation settles 2°, 0.18 s `power4.out`. Stamps hit as a `set` (no ease) on the word.
- Holds: every landed label is dead still. The camera is the only continuous mover.
- One hero move per beat; secondary moves 50–70 % of the distance, 0.1–0.2 s later.
- Transitions: the world is continuous; seams between scenes are camera moves (pan from line to pass, push into a ticket, pull back), never crossfades.

## SOUND (all recorded; licences in SOURCES.md)
| Sound | Marks exactly |
| --- | --- |
| thermal printer (two takes + one long) | a ticket printing: a new task or a printed fact |
| plate on steel (three takes) | an agent's work landing on the pass |
| plate scraped back | a plate sent back after failing the probe |
| service bell (two takes) | a plate passing the probe and going out. Twice in the film only |
| paper crumple | a belief broken by the facts (the FELT strip) |
| masking tape (three takes) | a tape label pressed down (only the 6 labels that name the idea) |
| kitchen timer ticking | the viewer's guess window (the two holds) |
| kitchen room tone (bed) | service running. Under voice at −30 dB relative to voice peak |

- No music. A music bed would be decoration (removing background music raised transfer d = 0.95); the room tone is the kitchen itself.
- The bed plays 0–69.4 s, **drops out** for the hard step (the pass, 69.4–101.7 s) and the metaphor break, returns at 109.8 s.
- The one moment it changes: at 126.4 s ("The cooks got fast") a sizzle layer joins the room tone - the kitchen is running right.
- Every hit 3–6 dB above the bed; peaks placed 1 frame after their picture; mix at −16 LUFS integrated, true peak ≤ −1 dBTP; voice is the loudest element.

## SHOTS (absolute seconds; cues are the spoken words)
1. **service 0–16.45** - Frame 0: printer slot close-up, a ticket half out. Printer feeds on "printer's" (3.4); tickets tear off and hang on the rail on "Fix" 6.7 / "Add" 8.2 / "cart" 9.6; on "software task" (12.3) the camera pulls back to the full rail; on "Every cook on this line" (13.4) the camera pans up to the range; on "AI agent" (15.2) tape AGENT 1–4 presses onto the four cooks.
2. **vibe 16.45–30.55** - Pan back down to the pass; Sam slides in at the bottom edge on "If" (16.6); an empty CHEF spot on "chef" (18.8); "VIBE CODING" tape on "vibe" (21.5); Karpathy ticket prints on "Karpathy" (23.1), "throwaway weekend projects" line on "throwaway" (25.8); plates start streaming across the pass with cloches on at "Accept all" (28.0), faster on "diffs" (29.5).
3. **call 30.55–55.1** - Stream freezes on "real jobs" (31.1); METR ticket prints: header on "METR" (34.0), "16 experienced devs" on "16" (34.6), "246 real tasks · AI on half, at random" on "half" (37.5); FASTER / SLOWER tapes on "Faster"/"slower" (39.4/39.9); timer ticks on "call" (41.0) until 44.0. "Slower" (44.1): SLOWER stamped. Time strips: WITHOUT AI 100 and WITH AI on "19%" (44.7) → 119, amber with "+19 %"; FELT strip 80 in red on "20%" (49.0). Sam turns to the strips on "Wait" (50.7). "Feeling fast" (52.6): FELT strip crumples onto the spike.
4. **bigger 55.1–69.45** - "by hand" (56.5): a single cook at a single board; "No" (57.1) ; "bigger" (58.6) printer feeds a longer ticket; doubling: ticket length ×2 on each beat from "length" (59.6) to "years" (65.5), camera zooming out ×2 each time (10 doublings), "+7 mo" per step, the 50 % line on "half the time" (62.2). "The cooks are real" (66.6) camera back to the line; "the pass" (68.5) pan down to an empty, dashed probe spot with tape THE PASS.
5. **pass 69.45–101.75 (hard step, no bed)** - The loop is drawn onto the kitchen, one part per word: cook on "agent" (69.9), MODEL tape on "model" (70.6), tools on "tools" (71.8), the marker loop arrow on "loop" (72.7), probe on "checking" (73.3). "build the check" (76.3): YOU BUILD THE CHECK tape; ticket gains an acceptance line on "tested" (78.9); tools tape on "tools" (80.3); probe labelled TESTS on "tests" (82.5). Plate lands on "Three items" (83.5) with code on it; EXPECT 0.30 on "expects" (85.6); "Will it pass?" hold with timer + rolling LCD to 89.5; readout 0.3 → 0.3000000000000000 → 4 (red) on "four" (92.7); plate slides back up the loop on "Back" (93.4) with a red note on "note" (95.7); returns on "Second try" (96.6); LCD 0.30 green on "30 cents" (97.5); bell + plate out on "Service" (98.2); marker tick on "passes" (99.6) and arrow → YOU on "comes"/"you" (100.4/100.9). *Changed in review:* the line was "After three tries, it comes to you" right after a plate passed on its second try; it now says "Once it passes, it comes to you" (re-voiced, same slot), and the 3 TRIES tape is gone.
6. **breaks 101.75–109.9** - Push in to one plate carrying two lines of code; tape WHERE IT BREAKS on "breaks" (103.1); the probe needle touches the tested row and reads green on "one spot" (104.5); the test on ticket #43 is underlined on "test" (105.5); the untested row (`applyCoupon`) turns red with "10% off → should be 0.27" on "wrote down" (106.8), while the probe still says PASS; marker ring + READ THE PLATE tape on "read" (108.5). (Built without the cloche: the probe-reads-one-spot picture already carries it.)
7. **name 109.9–132.48** - Karpathy ticket "FEB 2026" slides in on "Karpathy" (110.8) and prints his naming line (“…personally my current favorite ‘agentic engineering’”) on "named" (111.3); AGENTIC ENGINEERING tape on "agentic" (112.9); "not writing the code directly 99 % of the time" prints on "writing" (115.8); camera pulls back to the whole kitchen running on "orchestrating" (117.4); YOU spot at the pass on "oversight" (119.6); "art & science and expertise" prints on "art" (121.8); Sam at the pass holding the probe on "pass" (125.4); plates flow faster on "fast" (127.2); BUILD THE PASS tape on "Building" (127.7), bell, hold to 132.5.

## BANNED
The spec.md list (dark void, glow/neon/particles, purple-blue gradients, glass cards, cream-paper + serif + italic accent + mono caps labels, everything centred, everything fading in or sliding up, text moving while read, HUD/corner decoration, three cards in a row, docked logo), plus for this film:
- slides of bullet text; any frame that is only words with no kitchen object;
- icons in circles; a diagram drawn on a blank ground (the loop is drawn on the kitchen itself);
- music;
- red, green or amber used as decoration;
- the narrator's sentence printed on screen word for word.

Added after the fresh-eyes review (defaults it named, and what replaced them):
- dashed black wireframe outlines for "a spot" → floor-marking tape (`#E2CE86`);
- a card that appears empty and waits for its text (Karpathy ticket at 112 s) → a ticket shows only lines already printed, and prints the naming line on "named";
- a tape label for something the picture already shows (3 TRIES) → a marker tick on the green readout;
- a bar chart with no unit → "time to finish a task →" over the strips;
- a script line that contradicts the picture ("three tries" after a second-try pass) → line rewritten.

## QA frames
0.0 (thumbnail: printer + ticket), 15.6 (AGENT tapes), 29.0 (plates streaming), 42.5 (guess hold), 50.0 (three strips), 64.0 (doubling zoom), 88.0 (probe hold), 93.0 (red readout), 98.4 (green + out), 107.5 (un-probed corner), 113.5 (AGENTIC ENGINEERING), 130.0 (final).

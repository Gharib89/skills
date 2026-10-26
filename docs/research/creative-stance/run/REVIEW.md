# Review - "The Pass" (why agentic engineering)

Delivered: `../final.mp4`. 1920×1080, 30 fps, H.264 + AAC 48 kHz stereo, 132.5 s (ffprobe: 132.500 s on both streams).

## Creative calls (picked by me, with nobody to ask)
- **Concept: THE PASS**, out of three that differ in kind (STORYLINES.md):
  - A. a kitchen seen by one overhead camera;
  - B. a game show;
  - C. a nature documentary, the bold one.

  A won because a real kitchen pass *is* a verification loop. Ticket → cook with tools → plate → probe → send back or serve is the agent loop, so the metaphor carries the mechanism rather than decorating it. B had no place to show the loop. C's "agent as animal" breaks too early, because agents don't learn between sessions.
- **The misconception has a body.** Sam (day 1) says "just send it all out" while covered plates stream past an empty CHEF spot. The METR result then breaks it, and the FELT strip is crumpled onto the spike.
- **Asked before told.** There are two holds with a ticking timer:
  - "Faster or slower? Make your call" (41–44 s);
  - "Will it pass?" (87–89.5 s), with a rolling readout.
- **The metaphor says where it breaks**, as its own scene (102–109.9 s). The probe reads one spot green while the untested `applyCoupon` row is wrong: "you still read the plate".
- **Sound.** There's no music; the bed is kitchen room tone. It drops out for the hard step (the loop) and the metaphor break, comes back for the name, and a sizzle joins on "The cooks got fast". Every effect is a recorded CC0 file (SOURCES.md), and none are generated tones.
- **The voice:** local Kokoro, at about 155 wpm.

## What a stranger sees (contact sheet pulled from the delivered final.mp4, 39 frames)
- 0.5–9.8: a black printer pushes out a thermal ticket ("ORDER #41 FIX checkout bug"). More tickets hang on a rail. Restaurant orders that are software bugs.
- 15.9: four cooks seen from above at a range, with tape on each shoulder reading AGENT 1–4. The cooks are AI agents.
- 18–29.4: a cook taped "SAM · DAY 1" at the bottom edge, and an empty tape ring marked CHEF. "VIBE CODING" tape. Karpathy's "Accept All… don't read the diffs" ticket. Covered plates stream out past the empty chef spot. Nobody checks anything.
- 34.8–42.5: the METR ticket prints (16 experienced devs, 246 real issues, AI on a random half). FASTER / SLOWER tapes and a ticking timer: I'm being asked.
- 45.5–53.4: strips headed "time to finish a task →": without AI; with AI +19 % (longer); what they felt −20 % in red. Then the red strip is gone and a paper ball sits on a spike. They felt faster and were slower.
- 57.5–66: the cooks again, then a METR card with the tickets on the rail doubling, ×2 every ~7 months, 70 months ≈ 6 years. The work handed to agents keeps getting bigger.
- 69.5: an empty taped spot on the steel, marked THE PASS.
- 72.8–80.6: one cook ringed and taped MODEL, with knife and tongs and a TOOLS ticket. A loop is drawn from the cook down to a readout and back. An agent is a loop.
- 84.5–94.5: a plate carrying `total([0.10, 0.10, 0.10])`. The readout rolls numbers under a timer, lands on 0.30000000000000004 in red, and a FAIL note is pinned to the plate.
- 98.3–100.95: green "0.30 PASS", a marker tick, and an arrow to a YOU ring. Only checked work reaches me.
- 103.4–109.2: a big plate with two rows of code, "WHERE IT BREAKS". The probe touches one row and says PASS while the other row turns red ("10% off → should be 0.27"). Ringed: READ THE PLATE.
- 111.8–123: a Karpathy FEB 2026 ticket prints his naming line, then the AGENTIC ENGINEERING tape. The ticket adds "not writing the code directly 99%… orchestrating agents… oversight", then "an art & science and expertise". A wide shot of the whole kitchen with a YOU ring at the pass.
- 125.8–131.8: Sam stands in the YOU ring holding a probe. Plates arrive fast, each flashes green and goes out. BUILD THE PASS.

## Fresh-eyes review (a subagent that had not read the plan; stills only)
Its reconstruction of the story matched the intended one. It named these problems:

| It found | Done |
| --- | --- |
| Weakest frame, 112 s: the Karpathy ticket shows only a header (a "content failed to load" look) on the thesis beat | **Fixed.** Ticket lines no longer reserve space, and the ticket prints the naming line on "named" |
| Dashed black outlines (CHEF, the pass, YOU) read as wireframe placeholders | **Fixed.** Now floor-marking tape (`#E2CE86`) |
| "3 TRIES / YOU" was ambiguous | **Fixed, and it was a real script bug.** The voice said "After three tries" right after a plate passed on its second try. The line is re-voiced as "Once it passes, it comes to you", in the same slot (n18 got a 0.171 s hold so nothing after it moved). The 3 TRIES tape became a marker tick |
| "+19 %" had no unit | **Fixed.** "time to finish a task →" over the strips |
| Tape labels used for everything | **Partly.** Cut 3 TRIES. Each remaining tape names a word the voice says and the viewer should keep |
| FAIL note too small to read | **Fixed** (also flagged by `check`). The note is pinned at the close-up, larger, and the camera holds 0.9 s before pulling back |
| Plate overlaps rail tickets (105 s), tweet card covers two tickets (25.8 s), plates cross tickets | **Kept, and plate made smaller.** Paper laid on paper on a working counter is the medium |
| Red on the "felt" strip reads backwards | **Kept.** Red means "a belief the facts broke" throughout (SPEC LOOK) |
| Marker rings, repeated ticket row, cloned cooks, slogan ending | **Kept as choices.** The ring is the chef's marker and only lands on the word being said. The rail is the work queue and is meant to persist. The agents are interchangeable on purpose. "Building the pass is the job" is the thesis, not a call to action |
| Crops at frame edges (Sam at the bottom, "PASS" tape at the left in close-ups) | **Kept.** Sam stands at the bottom edge as the viewer's own position; the crops are camera framing, not layout overflow |

These defaults were also added to SPEC.md BANNED.

My own fixes from contact sheets before that:
- The loop arrowhead covered AGENT 3. The loop lines also cut through ticket text in every close-up, so I rerouted them round the rail.
- The timer covered ticket #40.
- The served plate slid under the probe.
- YOU was off the bottom of the frame.
- The red readout was on screen for only 0.08 s before the camera left. It now holds about 0.7 s.
- The READ THE PLATE ring drew on "reads" instead of "read", because the cue matched by word prefix.
- The METR ticket fed line 6 before its header, from the same prefix bug.
- Ticket #43 jumped height at the scene-4/5 cut.
- Amber "×2" on paper was 2.1:1 contrast. It's now `#C27F00` amber ink, 3.2:1.

## Measured (not heard)
I have not listened to this film. Everything below is a measurement.
- **Loudness (ffmpeg ebur128).**
  - Render: −19.2 LUFS integrated, −1.8 dBTP.
  - Mastered: two-pass loudnorm to **−16.0 LUFS integrated, true peak −1.5 dBTP, LRA 2.8 LU**. ffmpeg fell back to dynamic mode because the linear gain would have clipped peaks.
  - Video was stream-copied. Cross-correlating the master against the render shows a 0.0 ms offset at 0 s and 90 s.
- **Sync.** I subtracted the voice by least squares and found each hit's 5 ms-envelope peak.
  - 22 of 24 hits peak **+31 to +35 ms after their picture** (target: 1 frame = 33 ms). This holds for tapes, plates, crumple (on the ball hitting the spike), scrape (mid-slide) and the first bell.
  - The first render had tapes about 170 ms late and the scrape 295 ms late, because those files peak 0.13–0.64 s after their start. The fix starts each file early by its measured peak offset.
  - Two hits can't be isolated: BUILD THE PASS tape (−19 ms) and the final bell (−80 ms). Each lands within 50–150 ms of a plate landing, and the peak search finds the louder plate. They are placed by the same offset rule as the 22 that measured right.
- **Voice is loudest.** While the narrator speaks, the voice is louder than everything else combined in 99.7 % of 400 ms windows, by a median of 29 dB.
- **Bed by section** (RMS of the non-voice signal):
  - setup −45 dBFS;
  - hard step −51 dBFS;
  - metaphor break −55 dBFS;
  - name −46 dBFS;
  - final sizzle −30 dBFS.

  The hard step and the break have no bed clip at all; what remains there is the residual of the voice subtraction plus the timer, plates and scrape. So the bed does drop out under the hardest step and returns for the name.
- **Pace.** There are 98 distinct word-cued picture changes in 132.5 s, about 44 a minute. Many are small: a printed line or an underline. The longest stretch without one is 4.5 s, while the covered plates stream (29.5–34 s).
- **Not measured:** how the voice sounds (naturalness, mispronunciations). Whisper heard "Metair" for METR and "Carpathy" for Karpathy, so the TTS may say them oddly. A listen is the one check I couldn't do.

## Weakest shot
119.9 s, the whole-kitchen wide on "orchestrating agents". At 0.5× zoom everything except the layout is unreadable, and it only lasts ~2 s. It earns its place by showing four cooks working and one YOU spot, but it is the least legible frame. On a phone (review-phone sheet), ticket bodies, the plate code and the quote are unreadable throughout the wide shots. The tapes and the coloured readouts carry the meaning there.

## `hyperframes check` warnings kept (0 errors)
- **escaped_container / canvas_overflow / panel_out_of_canvas.** The kitchen is one 1920×2160 world under a moving camera, plus an 8000 px floor; it extends past the canvas by design.
- **text_below_floor.** Rail ticket headers ("TASK #41 19:42") at wide zoom. They are texture there and readable in every close-up.
- **contrast_aa_failure (METR "16", 36.8 s).** The checker sampled the printer body behind the half-printed ticket; on screen it is ink on paper.
- **line_unread (AGENT 3, 39.1 s).** A label passing during a camera move.

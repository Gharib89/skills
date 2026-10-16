# Own voice

An **own voice** narrates Arabic in a real person's voice: the default Arabic
narrator of the speaker's gender is voiced through Gemini, then converted on
this machine to an enrolled clip with Chatterbox VC. Enroll one only when the
user asks for their own voice.

1. **Consent.** Ask the user who the speaker is and to confirm that the
   speaker consents to narrating videos in this voice. Without a clear yes,
   enroll nothing. Keep their answer, word for word, as the statement.
2. **Enroll.** `node <skill>/scripts/voice/own-voice.mjs enroll <name> <clip>
   --gender female|male --consent "<statement>"`, `<name>` lowercase letters,
   digits and hyphens (`maya`), and `<clip>` 8 to 30 s of the speaker alone,
   in any format ffmpeg reads. It converts the clip to 24 kHz mono and stores
   it with the consent record in the user data store; enrolling a taken name
   replaces that voice. Exit 1 prints why: for a clip outside 8 to 30 s, ask
   for another clip; any other reason, relay it as printed. Exit 2 is usage.
3. **Use.** The brief's `voice=own:<name>`, with `language=ar`, names it.
   Setup's `--voice own:<name>` lists the rows it needs. A clip changed after
   enrollment has no consent record: enroll it again.
4. **Remove.** When the user withdraws consent or asks to remove the voice,
   `node <skill>/scripts/voice/own-voice.mjs remove <name>` deletes the clip
   and the consent record; a brief naming it is then refused.

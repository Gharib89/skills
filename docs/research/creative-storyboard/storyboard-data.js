// ---------- example video (the owner reacts to the shape, not this content) ----------
const VIDEO = {
  title: "How DNS finds a website",
  length: "14:00",
  lang: "English, own voice",
  chapters: [
    {
      n: 1,
      title: "A name, not a number",
      minutes: "4:00",
      focus: "Your machine, its cache, and the resolver taking the job",
      sources: "RFC 1034 s5.3.1; RFC 1035",
    },
    {
      n: 2,
      title: "The walk from root to answer",
      minutes: "5:30",
      focus: "Referrals from the root to .com to example.com; dig +trace",
      sources: "RFC 1034 s4.3; IANA root zone",
    },
    {
      n: 3,
      title: "Why it is fast, and why it goes stale",
      minutes: "4:30",
      focus: "TTLs, caching, a stale record, the propagation myth",
      sources: "RFC 2181 s8; RFC 8767",
    },
  ],
};

const DIRS = {
  switch: {
    name: "The Switchboard",
    kind: "A world",
    bold: true,
    rec: true,
    pitch:
      "A 1930s telephone exchange. Your request is a call; resolvers are operators who patch it board to board until someone knows the number. A rookie operator voices the wrong idea.",
    why: "DNS is a chain of referrals, and an exchange is a chain of referrals people already picture. The cable makes each hop visible.",
    breaks:
      "Breaks at caching: a real resolver remembers every answer for its TTL. Said in chapter 1, scene 5.",
    palette: [
      ["Walnut", "#2a1d15"],
      ["Brass", "#d1a94c"],
      ["Ivory", "#efe6d2"],
      ["Signal red", "#c0392b"],
    ],
    type: "Limelight titles, IBM Plex Mono for real names",
    voices: "Narrator (own voice), rookie operator (af_sky)",
    cues: "Jack click per hop, ring on an answer, low exchange hum bed",
  },
  direct: {
    name: "Draw it directly",
    kind: "The subject itself",
    bold: false,
    rec: false,
    pitch:
      "The real thing on screen: dig +trace output builds line by line, and each line becomes a labelled packet moving between machines on a white network diagram.",
    why: "Nothing to unlearn. The viewer leaves able to read real dig output.",
    breaks: "No metaphor, so nothing breaks; risk is the default diagram look.",
    palette: [
      ["Paper", "#fbfbf8"],
      ["Ink", "#111111"],
      ["Root violet", "#6b4fbb"],
      ["TLD orange", "#e07a1f"],
      ["Answer green", "#2e8b57"],
    ],
    type: "IBM Plex Mono throughout",
    voices: "Narrator (own voice)",
    cues: "Soft tick per packet, no bed under terminal steps",
  },
  quiz: {
    name: "Who Answers Next?",
    kind: "A format",
    bold: false,
    rec: false,
    pitch:
      "A game show. At every hop the viewer predicts which server answers; a buzzer and a scoreboard keep the guesses honest.",
    why: "Prediction is built into the format, so retrieval happens every minute.",
    breaks:
      "Breaks at speed: the real walk takes milliseconds, the show takes minutes. Said once, early.",
    palette: [
      ["Stage yellow", "#ffd23f"],
      ["Podium navy", "#14213d"],
      ["Buzzer pink", "#ee4266"],
      ["White", "#ffffff"],
    ],
    type: "Bungee titles, IBM Plex Sans captions",
    voices: "Host (own voice), contestant (af_sky), announcer (am_adam)",
    cues: "Buzzer, correct chime, crowd swell, upbeat bed",
  },
};
const DIR_ORDER = ["switch", "direct", "quiz"];

const S = (title, t, focus, screen, narr, notes) => ({
  title,
  t,
  focus,
  screen,
  narr,
  notes,
});
const SCENES = {
  1: [
    S(
      "Hard cut in",
      "0:00 to 0:35",
      0,
      "shop.example.com = ?",
      "You typed a name. Every packet on the internet needs a number. So who turns one into the other?",
      'Chapter mark on frame 1. Rookie: "Google knows every address."',
    ),
    S(
      "Make your call",
      "0:35 to 1:20",
      -1,
      "Who answers first?",
      "Before we follow it: who do you think answers first? Hold that guess.",
      "Prediction pause, 4 s with the bed only.",
    ),
    S(
      "Your own machine first",
      "1:20 to 2:10",
      1,
      "cache: miss",
      "The first stop is your own computer. It keeps recent answers. This name is new, so it has nothing.",
      "Cache shown empty; the rookie's guess fails.",
    ),
    S(
      "The resolver takes the job",
      "2:10 to 3:10",
      2,
      "resolver: I'll find it",
      "Your computer hands the question to a resolver, usually your provider's. It does the walking for you.",
      'Hand-off timed to "hands".',
    ),
    S(
      "Where the picture breaks",
      "3:10 to 4:00",
      3,
      "next: the root",
      "A real resolver remembers each answer for a while. Next chapter, the walk starts at the root.",
      "Says where the metaphor breaks; reach forward.",
    ),
  ],
  2: [
    S(
      "Reach back",
      "0:00 to 0:40",
      2,
      "who did you guess?",
      "Last chapter you guessed who answers first. Here is the walk.",
      "Retrieval frame, hard cut in.",
    ),
    S(
      "Ask the root",
      "0:40 to 2:00",
      3,
      ". : ask .com",
      "The root does not know the address. It knows who runs .com.",
      "First referral.",
    ),
    S(
      "Ask .com",
      "2:00 to 3:30",
      4,
      "com. : ask example.com",
      "The .com servers point one step further down.",
      "Second referral.",
    ),
    S(
      "The answer",
      "3:30 to 5:30",
      5,
      "93.184.215.14",
      "example.com's own server finally answers with the number.",
      "Ring on the answer.",
    ),
  ],
  3: [
    S(
      "Why it is fast",
      "0:00 to 1:30",
      1,
      "TTL 3600",
      "Every answer carries a time to live. Until it runs out, nobody walks again.",
      "Reach back to chapter 2's walk.",
    ),
    S(
      "A stale record",
      "1:30 to 3:00",
      1,
      "old number, still cached",
      "Change the record and old caches keep the old number until the TTL ends.",
      'Stage the wrong idea: "DNS propagates".',
    ),
    S(
      "The propagation myth",
      "3:00 to 4:30",
      2,
      "nothing propagates",
      "Nothing is pushed out. Caches expire, one by one.",
      "Close the arc.",
    ),
  ],
};

// The scenes maintainer/real-render.mjs renders: scene ids and component
// visuals as the compile stage writes them, each with its narration's seconds,
// not whole frames, so the padding is exercised. A slice adding a component
// adds its scenes here.
export const FIXTURE = [
  {
    scene: {
      id: "hook",
      role: "hook",
      title: "The promise",
      narration: ["One run, one merge."],
      visual: {
        component: "title",
        props: { kicker: "Ship", title: "Issue to pull request" },
      },
    },
    seconds: 2.37,
  },
  {
    scene: {
      id: "steps",
      role: "point",
      title: "The steps",
      narration: ["It reads the issue.", "Then it ships."],
      visual: {
        component: "cards",
        props: {
          items: [
            { at: 1, label: "Input", value: "issue" },
            { at: 2, label: "Then", value: "pull request" },
          ],
          emphasis: { target: "Input", at: 1 },
        },
      },
    },
    seconds: 1.91,
  },
  {
    scene: {
      id: "merge",
      role: "point",
      title: "The merge",
      narration: ["Then it merges."],
      visual: {
        component: "title",
        props: { kicker: "Ship", title: "Merged" },
      },
    },
    seconds: 1.43,
  },
  // Right to left: the type family `words` rises it by whole words, an English
  // term one unit, and the determinism check holds its frames.
  {
    dir: "rtl",
    scene: {
      id: "arabic",
      role: "point",
      title: "العربي",
      narration: ["بعد كده بيعمل merge."],
      visual: {
        component: "title",
        props: { title: "من issue لحد pull request", subtitle: "تشغيل واحد" },
      },
    },
    seconds: 1.67,
  },
  // Kinetic type read along: each word rises on its own spoken word, and the
  // rich component draws no push-in of the composer's.
  {
    scene: {
      id: "along",
      role: "point",
      title: "Read along",
      narration: ["Read the issue, ship it, merge it."],
      visual: {
        component: "words",
        props: {
          lines: [
            { at: 1, on: "Read the issue", text: "Read the issue" },
            { at: 1, on: "ship it", text: "ship it" },
          ],
        },
      },
    },
    seconds: 2.6,
  },
  // Numbers that count up: bars and stats, then the same right to left (a line
  // chart and a stat). Each number cues on a sentence after the scene's entry
  // seam, so a frame during the count is outside any seam.
  {
    scene: {
      id: "bars",
      role: "point",
      title: "Bars",
      narration: ["Latency was 900.", "Then it fell to 240.", "Quite a drop."],
      visual: {
        component: "chart",
        props: {
          kind: "bar",
          unit: "ms",
          items: [
            { at: 2, label: "Before", value: "900" },
            { at: 3, label: "After", value: "240" },
          ],
        },
      },
    },
    seconds: 3.4,
  },
  {
    scene: {
      id: "numbers",
      role: "point",
      title: "Numbers",
      narration: ["Two numbers.", "It holds 1,200 requests.", "In 40 ms."],
      visual: {
        component: "stat",
        props: {
          items: [
            { at: 2, value: "1,200", label: "requests a second" },
            { at: 3, value: "40", label: "milliseconds" },
          ],
        },
      },
    },
    seconds: 3.4,
  },
  {
    dir: "rtl",
    scene: {
      id: "arabic-line",
      role: "point",
      title: "خط",
      narration: ["الأرقام بتنزل.", "كانت 900.", "بقت 240."],
      visual: {
        component: "chart",
        props: {
          kind: "line",
          items: [
            { at: 2, label: "قبل", value: "900" },
            { at: 3, label: "بعد", value: "240" },
          ],
        },
      },
    },
    seconds: 3.4,
  },
  {
    dir: "rtl",
    scene: {
      id: "arabic-stat",
      role: "point",
      title: "أرقام",
      narration: ["رقمين.", "فيه 1,200 طلب.", "في ٤٠ ثانية."],
      visual: {
        component: "stat",
        props: {
          items: [
            { at: 2, value: "1,200", label: "طلب" },
            { at: 3, value: "٤٠", label: "ثانية" },
          ],
        },
      },
    },
    seconds: 3.4,
  },
  // A timeline, then an Arabic timeline and compare that run right to left
  // (the first event and the first side at the right), each item on its cue.
  {
    scene: {
      id: "timeline",
      role: "point",
      title: "Timeline",
      narration: ["How it grew.", "A side project.", "Then every team."],
      visual: {
        component: "timeline",
        props: {
          items: [
            { at: 2, when: "late 2019", label: "Started" },
            { at: 3, when: "Q3 2021", label: "Shipped", note: "every team" },
          ],
        },
      },
    },
    seconds: 3.4,
  },
  {
    dir: "rtl",
    scene: {
      id: "arabic-timeline",
      role: "point",
      title: "التاريخ",
      narration: ["إزاي كبر.", "بدأ مشروع جانبي.", "وبعدين كل الفرق."],
      visual: {
        component: "timeline",
        props: {
          items: [
            { at: 2, when: "أواخر 2019", label: "البداية" },
            { at: 3, when: "Q3 2021", label: "الانتشار" },
          ],
        },
      },
    },
    seconds: 3.4,
  },
  {
    dir: "rtl",
    scene: {
      id: "arabic-compare",
      role: "point",
      title: "مقارنة",
      narration: ["قبل وبعد.", "كان يدوي.", "بقى تلقائي."],
      visual: {
        component: "compare",
        props: {
          sides: [
            { title: "قبل", items: [{ at: 2, text: "يدوي" }] },
            { title: "بعد", items: [{ at: 3, text: "تلقائي" }] },
          ],
        },
      },
    },
    seconds: 3.4,
  },
  // A diagram the size a frame holds (5 columns, 3 nodes in one), packets on
  // most links and a reply beside its request, then an Arabic diagram that
  // runs right to left.
  {
    scene: {
      id: "diagram",
      role: "point",
      title: "Diagram",
      narration: [
        "A request comes in.",
        "The API queues the work.",
        "A worker stores the result.",
      ],
      visual: {
        component: "diagram",
        props: {
          nodes: [
            { id: "user", at: 1, label: "User" },
            { id: "api", at: 1, label: "API", note: "REST" },
            { id: "queue", at: 2, label: "Queue" },
            { id: "cache", at: 2, label: "Cache", note: "redis" },
            { id: "db", at: 2, label: "Database" },
            { id: "worker", at: 3, label: "Worker" },
            { id: "store", at: 3, label: "Store" },
          ],
          links: [
            { from: "user", to: "api", at: 1, packets: 2 },
            { from: "api", to: "queue", at: 2, packets: 1 },
            { from: "api", to: "cache", at: 2 },
            { from: "api", to: "db", at: 2 },
            { from: "api", to: "user", at: 2, packets: 1 },
            { from: "queue", to: "worker", at: 3, packets: 1 },
            { from: "worker", to: "store", at: 3, packets: 1 },
          ],
        },
      },
    },
    seconds: 3.4,
  },
  {
    dir: "rtl",
    scene: {
      id: "arabic-diagram",
      role: "point",
      title: "مخطط",
      narration: ["الطلب يوصل.", "الخادم يقرا.", "وبعدين يرد."],
      visual: {
        component: "diagram",
        props: {
          nodes: [
            { id: "client", at: 1, label: "العميل" },
            { id: "server", at: 2, label: "الخادم" },
            { id: "cache", at: 2, label: "الكاش", note: "redis" },
          ],
          links: [
            { from: "client", to: "server", at: 2, packets: 2 },
            { from: "server", to: "cache", at: 2, packets: 1 },
            { from: "server", to: "client", at: 3, packets: 1 },
          ],
        },
      },
    },
    seconds: 3.4,
  },
  // A browser page: the cursor moves, text is typed a whole word at a time and
  // a button is clicked, each on its sentence's cue (the first sentence's is
  // under the entry seam). Then the same page in Arabic, which runs right to
  // left with its URL left to right and types an English term as one word.
  {
    scene: {
      id: "browser",
      role: "point",
      title: "Browser",
      narration: ["Open the page.", "Type the name.", "Press the button."],
      visual: {
        component: "browser",
        props: {
          url: "example.com/signup",
          title: "Sign up",
          elements: [
            { id: "head", kind: "heading", text: "Create an account" },
            { id: "name", kind: "field", text: "Your name" },
            { id: "go", kind: "button", text: "Continue" },
          ],
          actions: [
            { at: 1, target: "head", act: "move" },
            { at: 2, target: "name", act: "type", text: "Ada Lovelace" },
            { at: 3, target: "go", act: "click" },
          ],
        },
      },
    },
    seconds: 3.4,
  },
  {
    dir: "rtl",
    scene: {
      id: "arabic-browser",
      role: "point",
      title: "متصفح",
      narration: ["افتح الصفحة.", "اكتب الطلب.", "اضغط الزر."],
      visual: {
        component: "browser",
        props: {
          url: "example.com/new",
          title: "طلب جديد",
          elements: [
            { id: "head", kind: "heading", text: "إنشاء طلب" },
            { id: "name", kind: "field", text: "العنوان" },
            { id: "go", kind: "button", text: "متابعة" },
          ],
          actions: [
            { at: 1, target: "head", act: "move" },
            {
              at: 2,
              target: "name",
              act: "type",
              text: "اكتب pull request هنا",
            },
            { at: 3, target: "go", act: "click" },
          ],
        },
      },
    },
    seconds: 3.4,
  },
];

/* ---- boot: the browser only. Wires the capabilities, the live cards, drafts, live colours and Submit. ---- */
if (typeof document !== "undefined") boot();

async function boot() {
  const S = newState(document.title);
  const app = document.getElementById("app");
  const key = () => "card-draft-" + latest(S).version;
  const saveDraft = () => {
    try {
      localStorage.setItem(key(), JSON.stringify(draftOf(S)));
    } catch (e) {}
  };
  function restoreDraft() {
    let saved = null;
    try {
      saved = JSON.parse(localStorage.getItem(key()) || "null");
    } catch (e) {}
    if (!saved || S.drafts[latest(S).version]) return;
    const d = draftOf(S);
    for (const f of ["colors", "type"])
      for (const [k, v] of Object.entries(saved[f] || {}))
        if (k in d[f] && typeof v === "string") d[f][k] = v;
    for (const f of ["name", "note"])
      if (typeof saved[f] === "string") d[f] = saved[f];
    for (const f of ["replace", "default"])
      if (typeof saved[f] === "boolean") d[f] = saved[f];
    if (CHOICES.some((x) => x[0] === saved.choice)) d.choice = saved.choice;
  }
  // Each frame is drawn at 1920x1080 and scaled to its box.
  function fit() {
    document.querySelectorAll(".frame").forEach((b) => {
      for (const f of b.children)
        f.style.transform = `scale(${b.clientWidth / 1920})`;
    });
  }
  // Live colours: the frames keep their documents and take the edited palette.
  function repaint() {
    if (!latest(S)) return;
    document.querySelectorAll("iframe[data-frame]").forEach((f) => {
      const s = f.contentDocument && f.contentDocument.getElementById("edits");
      if (s) s.textContent = paletteCss(S);
    });
    for (const el of lives())
      if (el.dataset.ready) say(el, { type: "css", css: paletteCss(S) });
  }

  // ---- live builds. The build is a script asset, so it loads the same from a published page and from
  // file:. It plays in a frame with no origin: the page hands it fonts and commands by postMessage. ----
  let loaded = null,
    loadedUrl = null;
  function loadBuild(c) {
    const url = buildUrl(c);
    if (!url) return Promise.resolve(null);
    if (loadedUrl !== url) {
      loadedUrl = url;
      loaded = new Promise((done) => {
        const el = document.createElement("script");
        el.src = url;
        el.onload = () => done(window.__build);
        el.onerror = () => done(null);
        document.head.append(el);
      });
    }
    return loaded;
  }
  // Each face's bytes are decoded once and sent as a copy: a transfer would empty the original.
  const fontsOf = (build) => {
    build.bytes ||= build.fonts.map((x) => ({
      ...x,
      data: Uint8Array.from(atob(x.data), (c) => c.charCodeAt(0)).buffer,
    }));
    return build.bytes.map((x) => ({ ...x, data: x.data.slice(0) }));
  };
  const lives = () => [...document.querySelectorAll("iframe[data-live]")];
  const say = (el, m) =>
    el.contentWindow && el.contentWindow.postMessage(m, "*");
  async function mount() {
    const todo = lives().filter((el) => !el.dataset.started);
    if (!todo.length) return;
    todo.forEach((el) => (el.dataset.started = "1"));
    const build = await loadBuild(latest(S));
    if (build)
      for (const el of todo) if (el.isConnected) el.srcdoc = build.html;
  }
  addEventListener("message", async (e) => {
    const el = lives().find((x) => x.contentWindow === e.source);
    const type = el && e.data && e.data.type;
    if (type === "ready") {
      const build = await loadBuild(latest(S));
      if (build) say(el, { type: "fonts", fonts: fontsOf(build) });
    } else if (type === "shown") {
      el.dataset.ready = "1";
      const [from, to] = latest(S).frames.find(
        (f) => f.id === el.dataset.live,
      ).loop;
      say(el, { type: "css", css: paletteCss(S) });
      say(el, { type: "run", from, to, loop: true });
    }
  });
  // One frame plays its build, the one most in view; the rest show their poster.
  const ratios = {};
  const io = new IntersectionObserver(
    (entries) => {
      for (const e of entries)
        ratios[e.target.dataset.stage] = e.isIntersecting
          ? e.intersectionRatio
          : 0;
      const cur = Object.keys(S.inView)[0] || null;
      const top = Object.keys(ratios).reduce(
        (m, id) => (ratios[id] > (ratios[m] || 0) ? id : m),
        "",
      );
      const pick = cur && ratios[cur] >= 0.5 ? cur : top;
      const next = pick && ratios[pick] >= 0.5 ? pick : null;
      if (next === cur) return;
      S.inView = next ? { [next]: true } : {};
      render();
    },
    { threshold: [0, 0.5, 1] },
  );
  function watch() {
    io.disconnect();
    for (const k of Object.keys(ratios)) delete ratios[k];
    document
      .querySelectorAll(".frame[data-stage]")
      .forEach((el) => io.observe(el));
  }
  function render() {
    const f = document.activeElement,
      fid = f && (f.id || null);
    const t = document.createElement("template");
    // The frames reload here, their documents built with the edited palette.
    t.innerHTML = view(S);
    app.replaceChildren(t.content);
    const el = fid && document.getElementById(fid);
    if (el) el.focus({ preventScroll: true });
    fit();
    repaint();
    watch();
    mount();
  }
  // While typing: only the parts that follow the edit change, so the input keeps its caret.
  function refresh() {
    const t = document.createElement("template");
    t.innerHTML = view(S);
    document.querySelectorAll("[data-live]").forEach((el) => {
      const n = t.content.querySelector(`[data-live="${el.dataset.live}"]`);
      if (n) el.replaceWith(n);
    });
    repaint();
  }
  addEventListener("resize", fit);
  render();
  // Listeners first: a local page returns before the capabilities below.
  document.addEventListener("click", (e) => {
    const t = e.target.closest("[data-act]");
    if (!t || t.disabled) return;
    const act = t.dataset.act;
    if (act === "submit") return submit(t);
    if (act === "wake") return rewake(t);
    if (act === "copy") return copy();
  });
  document.addEventListener("change", (e) => {
    const t = e.target;
    if (t.name === "choice") ACT.set(S, { field: "choice", value: t.value });
    else if (t.type === "checkbox" && t.dataset.set)
      ACT.set(S, { field: t.dataset.set, value: t.checked });
    else if (t.dataset.font)
      ACT.font(S, { role: t.dataset.font, font: t.value });
    else return;
    saveDraft();
    render();
  });
  document.addEventListener("input", (e) => {
    const t = e.target,
      token = t.dataset.color || t.dataset.hex;
    if (token) {
      const v = t.value.trim();
      ACT.color(S, { token, hex: v });
      // The picker and the hex field show one value; the picker takes only a whole colour.
      const other = document.getElementById(
        (t.dataset.color ? "hex-" : "pick-") + token,
      );
      if (other && HEX.test(v))
        other.value = t.dataset.color ? v : v.toLowerCase();
    } else if (t.dataset.set === "name" || t.dataset.set === "note")
      ACT.set(S, { field: t.dataset.set, value: t.value });
    else return;
    saveDraft();
    refresh();
  });

  const embedded = () => {
    try {
      return JSON.parse(document.getElementById("card").textContent);
    } catch (e) {
      return null;
    }
  };
  function localMode() {
    const doc = embedded();
    if (!doc || typeof doc !== "object") {
      S.mode = "nodb";
      render();
      return;
    }
    S.local = true;
    setCards(S, [doc]);
    restoreDraft();
    render();
  }
  const use = (n) =>
    window.claude && window.claude.use
      ? window.claude.use(n).catch(() => null)
      : Promise.resolve(null);
  // Declared before the await, not as a const destructure: the listeners above
  // read them, and one fired during the await would hit the TDZ.
  let db = null,
    comments = null,
    user = null;
  [db, comments, user] = await Promise.all([
    use("db"),
    use("comments"),
    use("user"),
  ]);
  if (!db) return localMode();
  if (user) S.canEdit = await user.canEdit().catch(() => true);

  db.collection("cards")
    .orderBy("version")
    .onSnapshot(
      (snap) => {
        const was = latest(S) && latest(S).version;
        setCards(
          S,
          snap.docs.map((d) => d.data()),
        );
        if (latest(S) && latest(S).version !== was) restoreDraft();
        render();
      },
      () => {
        S.mode = "nodb";
        render();
      },
    );
  db.collection("answers").onSnapshot(
    (snap) => {
      setAnswers(
        S,
        snap.docs.map((d) => d.data()),
      );
      render();
    },
    () => {},
  );

  // The comment is the doorbell: the one page action that starts a turn in the watching session.
  // It carries the answers too, cut to the 4 KiB a comment holds.
  function capped(text) {
    const enc = new TextEncoder(),
      tail = `\n[cut to fit: read answers/card-${latest(S).version}]`;
    if (enc.encode(text).length <= 4096) return text;
    let s = text;
    while (enc.encode(s + tail).length > 4096) s = s.slice(0, -64);
    return s + tail;
  }
  async function wake(anchor) {
    if (!comments || !anchor) return false;
    try {
      if ((await comments.canSendToClaude()) !== "available") return false;
      await comments.sendToClaude({ anchor, text: capped(answersText(S)) });
      return true;
    } catch (e) {
      return false;
    }
  }
  const anchorOf = (el) =>
    comments ? comments.anchorFor(el).catch(() => null) : Promise.resolve(null);
  async function submit(btn) {
    if (!canSubmit(S) && S.status !== "neither") return;
    // Lock before any await, so a second click finds the card locked.
    const doc = answersDoc(S);
    S.status = "sending";
    render();
    const anchor = await anchorOf(document.getElementById(btn.id) || btn);
    const saved = await db
      .doc("answers/card-" + doc.version)
      .set(doc)
      .then(
        () => true,
        () => false,
      );
    const woke = await wake(anchor),
      text = answersText(S);
    S.status = outcome(saved, woke, capped(text) === text);
    render();
  }
  async function rewake(btn) {
    if (S.status !== "saved") return;
    S.status = "sending";
    render();
    const anchor = await anchorOf(document.getElementById("submit") || btn);
    S.status = (await wake(anchor)) ? "sent" : "saved";
    render();
  }
  function copy() {
    const note = (t) => {
      const c = document.getElementById("copied");
      if (c) c.textContent = t;
    };
    const selectIt = () => {
      const r = document.createRange();
      r.selectNodeContents(document.getElementById("fallback-text"));
      const s = getSelection();
      s.removeAllRanges();
      s.addRange(r);
      note("Selected: press Ctrl+C or Cmd+C");
    };
    try {
      navigator.clipboard
        .writeText(answersText(S))
        .then(() => note("Copied"), selectIt);
    } catch (e) {
      selectIt();
    }
  }
}

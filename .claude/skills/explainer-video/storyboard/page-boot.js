/* ---- boot: the browser only. Wires the capabilities, the live boards, drafts, the live builds, the animatic and Submit. ---- */
if (typeof document !== "undefined") boot();

async function boot() {
  const S = newState(document.title);
  const app = document.getElementById("app");
  const key = () => "board-draft-" + latest(S).version;
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
    for (const f of ["choices", "narr", "notes", "brief", "kept"])
      for (const [k, v] of Object.entries(saved[f] || {}))
        if (k in d[f] && (typeof v === "string" || v === null)) d[f][k] = v;
    for (const [id, picks] of Object.entries(saved.picks || {}))
      for (const [m, v] of Object.entries(picks))
        if (id in d.picks && typeof v === "string") d.picks[id][m] = v;
    for (const [id, v] of Object.entries(saved.was || {}))
      if (id in d.picks && typeof v === "string") d.was[id] = v;
  }
  function render() {
    const f = document.activeElement,
      fid = f && (f.id || null);
    const t = document.createElement("template");
    t.innerHTML = view(S);
    // Playing media outlives a render. Each audio element is moved over its fresh twin. A live frame is
    // moved with moveBefore, which keeps its document where any other move reloads it; one with no
    // twin (its card left the view) is dropped, and a twin with no frame starts in mount().
    for (const audio of app.querySelectorAll("audio[id], audio[data-audio]")) {
      const twin = audio.id
        ? t.content.getElementById(audio.id)
        : [...t.content.querySelectorAll("[data-audio]")].find(
            (x) => x.dataset.audio === audio.dataset.audio,
          );
      // A revision with the same ids but another file must not keep playing the old one.
      if (twin && twin.getAttribute("src") === audio.getAttribute("src"))
        twin.replaceWith(audio);
      else audio.pause();
    }
    const frames = [...app.querySelectorAll("iframe[data-live]")],
      olds = [...app.childNodes],
      slots = [...t.content.querySelectorAll("iframe[data-live]")];
    app.append(t.content);
    for (const fr of frames) {
      const slot = slots.find((x) => x.dataset.live === fr.dataset.live);
      if (slot && app.moveBefore) {
        slot.parentNode.moveBefore(fr, slot);
        slot.remove();
      }
    }
    olds.forEach((n) => n.remove());
    const el = fid && document.getElementById(fid);
    if (el) el.focus({ preventScroll: true });
    watch();
    mount();
  }
  function refresh() {
    const b = latest(S);
    if (!b) return;
    document.querySelectorAll("[data-ready]").forEach((el) => {
      el.textContent = b.scenes.filter(needs).length - todoN(S);
    });
    document
      .querySelectorAll('[data-act="submit"], [data-act="copy"]')
      .forEach((x) => {
        x.disabled = S.local ? todoN(S) > 0 : !canSubmit(S);
      });
    // A note or an edit flips its card's answer: the radios follow in place, so typing keeps focus.
    document.querySelectorAll('input[type="radio"][data-id]').forEach((r) => {
      r.checked = draftOf(S).choices[r.dataset.id] === r.value;
    });
    const ft = document.getElementById("fallback-text");
    if (ft) ft.textContent = answersText(S);
  }
  // Listeners first: a local page returns before the capabilities below.
  document.addEventListener("click", (e) => {
    const t = e.target.closest("[data-act]");
    if (!t || t.disabled) return;
    const act = t.dataset.act;
    if (act === "approve-all") {
      ACT.approveAll(S);
      saveDraft();
      render();
      // A local page has no Submit: the answers are copied from the bar.
      return S.local || !canSubmit(S)
        ? null
        : submit(document.getElementById("submit"));
    }
    if (act === "submit") return submit(t);
    if (act === "wake") return rewake(t);
    if (act === "copy") return copy();
    if (act === "play") return playAnimatic(0);
    if (act === "jump") return playAnimatic(sceneOf(t.dataset.id).start);
    if (act === "card-play") return cardPlay(t.dataset.id);
    if (act === "stop") return stop();
  });
  document.addEventListener("change", (e) => {
    const t = e.target;
    // A menu answers its card Revise; a brief menu re-renders so the voices follow the language.
    if (t.matches("select[data-menu]"))
      ACT.pick(S, { id: t.dataset.id, menu: t.dataset.menu, value: t.value });
    else if (t.matches("select[data-brief]"))
      ACT.brief(S, { knob: t.dataset.brief, value: t.value });
    else if (t.matches('input[type="radio"][data-id]'))
      ACT.choose(S, { id: t.dataset.id, choice: t.value });
    else return;
    saveDraft();
    render();
  });
  document.addEventListener("input", (e) => {
    const t = e.target;
    if (t.dataset.field)
      ACT.field(S, {
        id: t.dataset.id,
        field: t.dataset.field,
        value: t.value,
      });
    else if (t.dataset.brief)
      ACT.brief(S, { knob: t.dataset.brief, value: t.value });
    else if (t.dataset.kept)
      ACT.kept(S, { term: t.dataset.kept, value: t.value });
    else return;
    saveDraft();
    refresh();
  });

  // ---- live builds. The build is a script asset, so it loads the same from a published page and from
  // file:. It plays in a frame with no origin: the page hands it fonts and commands by postMessage. ----
  let loaded = null,
    loadedUrl = null;
  function loadBuild(b) {
    const url = buildOf(b);
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
  const frames = () => [...document.querySelectorAll("iframe[data-live]")];
  const frameOf = (id) => frames().find((x) => x.dataset.live === id);
  const sceneOf = (id) => latest(S).scenes.find((x) => x.id === id);
  const say = (el, m) => el.contentWindow.postMessage(m, "*");
  // A frame with no origin can only be answered at "*"; its window is told apart by identity.
  async function mount() {
    const todo = [
      ...document.querySelectorAll("iframe[data-live]:not([data-started])"),
    ];
    if (!todo.length) return;
    todo.forEach((el) => (el.dataset.started = "1"));
    const build = await loadBuild(latest(S));
    if (build)
      for (const el of todo) if (el.isConnected) el.srcdoc = build.html;
  }
  let solo = null;
  addEventListener("message", async (e) => {
    const el = frames().find((x) => x.contentWindow === e.source);
    const type = el && e.data && e.data.type;
    if (type === "ready")
      say(el, { type: "fonts", fonts: fontsOf(await loadBuild(latest(S))) });
    else if (type === "shown") {
      el.dataset.ready = "1";
      drive(el);
    } else if (type === "done" && el.dataset.live === solo) {
      solo = null;
      drive(el);
    }
  });
  // A card's frame loops its slot; the animatic's follows the narration.
  function drive(el) {
    if (el.dataset.live === "animatic") return seek();
    const [from, to] = loopOf(sceneOf(el.dataset.live));
    say(el, { type: "run", from, to, loop: true });
  }
  // One card mounts its build, the one most in view; the rest show their poster.
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
  // The frame is a 1920 by 1080 page scaled to its stage.
  const ro = new ResizeObserver((entries) => {
    for (const e of entries)
      e.target.style.setProperty("--k", e.contentRect.width / 1920);
  });
  function watch() {
    io.disconnect();
    for (const k of Object.keys(ratios)) delete ratios[k];
    for (const el of document.querySelectorAll(".stage[data-stage]")) {
      ro.observe(el);
      if (el.dataset.stage !== "animatic") io.observe(el);
    }
  }
  const dropFrames = () =>
    document.querySelectorAll("iframe[data-live]").forEach((x) => x.remove());

  // Play on a card: its slot once, with its own narration; the loop resumes when it is done.
  // Only a card whose build is showing plays: narration over a poster would have no motion to judge.
  const quiet = () =>
    document.querySelectorAll("audio").forEach((x) => x.pause());
  function cardPlay(id) {
    const el = frameOf(id);
    if (!el || !el.dataset.ready) return;
    const a = [...document.querySelectorAll("[data-audio]")].find(
      (x) => x.dataset.audio === id,
    );
    quiet();
    a.currentTime = 0;
    const [from, to] = loopOf(sceneOf(id));
    // The motion starts with the narration, so a slow or refused play() never runs it alone.
    a.play().then(
      () => {
        solo = id;
        say(el, { type: "run", from, to, loop: false });
      },
      () => {},
    );
  }

  // The animatic: the one build, seeked to the narration's clock, the playing card ringed and listed.
  const narration = () => document.getElementById("player-audio");
  let raf = 0;
  // Narration waits for the animatic's frame, so the opening is not heard over the poster.
  let waiting = false;
  function seek() {
    const el = frameOf("animatic");
    if (el && el.dataset.ready)
      say(el, { type: "seek", t: narration().currentTime });
  }
  function tick() {
    if (waiting && frameOf("animatic")?.dataset.ready) {
      waiting = false;
      narration()
        .play()
        .catch(() => {});
    }
    const on = sceneAt(latest(S), narration().currentTime).id;
    seek();
    if (on !== S.playing) {
      S.playing = on;
      // In place: a render without moveBefore (Firefox, Safari) would reload the playing frame at
      // every scene change, where the seams are.
      for (const el of document.querySelectorAll(".scene")) {
        el.classList.toggle("on", el.dataset.id === on);
        if (el.dataset.id === on) el.setAttribute("aria-current", "true");
        else el.removeAttribute("aria-current");
      }
      for (const el of document.querySelectorAll("[data-card]"))
        el.classList.toggle("playing", el.dataset.card === on);
    }
    raf = requestAnimationFrame(tick);
  }
  function stop() {
    cancelAnimationFrame(raf);
    waiting = false;
    narration().pause();
    S.animatic = false;
    S.playing = null;
    render();
  }
  function playAnimatic(t) {
    quiet();
    S.animatic = true;
    S.playing = sceneAt(latest(S), t).id;
    render();
    const a = narration();
    a.currentTime = t;
    a.onended = stop;
    waiting = true;
    cancelAnimationFrame(raf);
    raf = requestAnimationFrame(tick);
  }

  // After the observers above, which every render reads.
  render();
  const embedded = () => {
    try {
      return JSON.parse(document.getElementById("board").textContent);
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
    setBoards(S, [doc]);
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

  db.collection("boards")
    .orderBy("version")
    .onSnapshot(
      (snap) => {
        const was = latest(S) && latest(S).version;
        setBoards(
          S,
          snap.docs.map((d) => d.data()),
        );
        if (latest(S) && latest(S).version !== was) {
          restoreDraft();
          // A revised board leaves the old animatic stopped, driver included.
          cancelAnimationFrame(raf);
          waiting = false;
          S.animatic = false;
          S.playing = null;
          dropFrames();
        }
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
      tail = `\n[cut to fit: read answers/board-${latest(S).version}]`;
    if (enc.encode(text).length <= 4096) return text;
    let s = text;
    while (enc.encode(s + tail).length > 4096) s = s.slice(0, -64);
    return s + tail;
  }
  async function wake(anchor) {
    if (!comments || !anchor) return false;
    try {
      // `available` means this viewer may send, not that a session is watching: a send with no watch
      // lands and wakes nothing, so the sent receipt still names the typed fallback.
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
    // Lock before any await, so a second click finds the board locked.
    const doc = answersDoc(S);
    S.status = "sending";
    render();
    const anchor = await anchorOf(document.getElementById(btn.id) || btn);
    const saved = await db
      .doc("answers/board-" + doc.version)
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

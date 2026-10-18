/* ---- boot: the browser only. Wires the capabilities, the live boards, drafts, the animatic and Submit. ---- */
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
  }
  function render() {
    const f = document.activeElement,
      fid = f && (f.id || null);
    const t = document.createElement("template");
    t.innerHTML = view(S);
    // The player keeps its audio element across renders so a playing animatic is not cut off.
    const old = document.getElementById("player"),
      fresh = t.content.getElementById("player");
    if (old && fresh) {
      old.querySelector("#player-still").src = fresh
        .querySelector("#player-still")
        .getAttribute("src");
      fresh.replaceWith(old);
    }
    app.replaceChildren(t.content);
    const el = fid && document.getElementById(fid);
    if (el) el.focus({ preventScroll: true });
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
    const ft = document.getElementById("fallback-text");
    if (ft) ft.textContent = answersText(S);
  }
  render();
  // Listeners first: a local page returns before the capabilities below.
  document.addEventListener("click", (e) => {
    const t = e.target.closest("[data-act]");
    if (!t || t.disabled) return;
    const act = t.dataset.act;
    if (act === "submit") return submit(t);
    if (act === "wake") return rewake(t);
    if (act === "copy") return copy();
    if (act === "play") return playFrom(0);
    if (act === "stop") return stop();
  });
  document.addEventListener("change", (e) => {
    const t = e.target;
    if (!t.matches('input[type="radio"][data-id]')) return;
    ACT.choose(S, { id: t.dataset.id, choice: t.value });
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

  // The animatic: each card's narration in order, its still shown and its card ringed.
  const audio = () => document.getElementById("player-audio");
  function stop() {
    const a = audio();
    if (a) a.pause();
    S.playing = null;
    render();
  }
  function playFrom(i) {
    const c = latest(S) && latest(S).scenes[i];
    if (!c) {
      S.playing = null;
      render();
      return;
    }
    S.playing = c.id;
    render();
    const a = audio();
    a.src = mediaUrl(c.audio);
    a.onended = () => playFrom(i + 1);
    a.play().catch(() => {});
  }

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

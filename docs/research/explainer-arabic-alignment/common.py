# Shared helpers: audio load, script tokenising, transliteration-aware keys, word matching.
import re, subprocess, unicodedata
import numpy as np
SR = 16000
STOP = set("""اللي لما على علي في فيه من ده دي دا و بس كل لحد ما عن مع بعد كده قبل لو ولا إيه ايه هي هو عشان
اللى الى إلى الي ل ب يا انا أنا انت إنت ليها ليه بتاع بتاعك بتاعة وبعدين بعدها وبعدها نفس أي اي
the a an of to for and or in on""".split())
TASHKEEL = re.compile("[ً-ْٰـ]")
PUNCT = re.compile(r"[^\w\sـ]")
LATIN = re.compile(r"[A-Za-z]")


def load(path):
    pcm = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(pcm, np.float32).copy()


def ar_norm(s):
    s = unicodedata.normalize("NFKC", s)
    s = TASHKEEL.sub("", s)
    return re.sub("[أإآ]", "ا", s).replace("ى", "ي").replace("ة", "ه")


def script_words(text):
    """Script -> caption words. A clitic written with tatweel (الـ, لـ, للـ) glues to the next word,
    since it is spoken as one prosodic word. Returns list of (display, bare) where bare drops the clitic."""
    raw = PUNCT.sub(" ", re.sub("[\u064b-\u0652\u0670]", "", text).replace("،", " ").replace("؟", " ")).split()
    out, pre = [], ""
    for w in raw:
        if w.endswith("ـ"):
            pre += w + " "
            continue
        out.append((pre + w, w))
        pre = ""
    return out


def is_content(bare):
    return ar_norm(bare).lower() not in STOP and len(bare) > 1


AR = dict(zip("بتثجحخدذرزسشصضطظغفقكلمنه", "bttjhxddrssSsdtdgfkklmnh"))
LETTER = dict(zip("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "ei bi si di i ef ji eitsh ay jei kei el em en o bi kyu ar es ti yu fi dablyu eks way zed".split()))
EN_RULES = (("tch", "S"), ("sh", "S"), ("ch", "S"), ("th", "t"), ("ph", "f"), ("ck", "k"), ("qu", "k"),
            ("ce", "se"), ("ci", "si"), ("c", "k"), ("q", "k"), ("p", "b"), ("v", "f"), ("g", "j"), ("z", "s"), ("x", "ks"))


def key(word):
    """Script-independent consonant key. Arabic letters map to a consonant class (vowel letters,
    hamza and ain drop); English spelling folds into the same classes, so 'push' and 'بوش' both
    give 'bS'. A leading Arabic article and its proclitic drop."""
    w = ar_norm(word).replace("\u0640", "").replace(" ", "")
    if re.fullmatch("(و|ف|ب|ل)?(ال|ل)?[A-Z]{2,4}", w):  # acronym: spoken as letter names
        w = re.sub("^[^A-Z]*", "", w)
        w = "".join(LETTER[ch] for ch in w)
    if LATIN.search(w):
        w = re.sub("^(و|ف|ب|ل)?(ال|ل)", "", w).lower()
        for a, b in EN_RULES:
            w = w.replace(a, b)
        k = re.sub("[^a-zS]", "", w)
        k = re.sub("[aeiouwy]", "", k)
    else:
        w = re.sub("^(و|ف|ب|ل)?ال(?=..)", "", w)
        k = "".join(AR.get(ch, "") for ch in w)
    return re.sub(r"(.)\1+", r"\1", k)


def lev(a, b):
    d = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        p, d[0] = d[0], i
        for j, y in enumerate(b, 1):
            p, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, p + (x != y))
    return d[-1]


def sim(a, b):
    if len(a) < 2 or len(b) < 2:
        return float(a == b)
    return 1 - lev(a, b) / max(len(a), len(b))


def match(ref_keys, hyp_keys, tau=0.5):
    """Monotonic alignment maximising summed similarity. A ref word may match 1-3 consecutive hyp words
    (Whisper splits 'worktree' into 'وورك تري'); two ref words may match one hyp word.
    Returns per-ref (sim, (j0, j1)) or (0, None)."""
    n, m = len(ref_keys), len(hyp_keys)
    NEG = -1.0
    best = np.full((n + 1, m + 1), NEG)
    back = {}
    best[0, :] = 0
    best[:, 0] = 0
    for i in range(n + 1):
        for j in range(m + 1):
            if i == 0 and j == 0:
                continue
            cands = []
            if i > 0:
                cands.append((best[i - 1, j], ("skipref", 1, 0)))
            if j > 0:
                cands.append((best[i, j - 1], ("skiphyp", 0, 1)))
            for di, dj in ((1, 1), (1, 2), (1, 3), (2, 1)):
                if i >= di and j >= dj:
                    s = sim("".join(ref_keys[i - di:i]), "".join(hyp_keys[j - dj:j]))
                    if s >= tau:
                        cands.append((best[i - di, j - dj] + s * di, ("match", di, dj, s)))
            v, op = max(cands, key=lambda c: c[0])
            best[i, j] = v
            back[i, j] = op
    res = [(0.0, None)] * n
    i, j = n, m
    while i > 0 and j > 0:
        op = back[i, j]
        if op[0] == "match":
            _, di, dj, s = op
            for k in range(i - di, i):
                res[k] = (s, (j - dj, j - 1))
        i, j = i - op[1], j - op[2]
    return res


def recall(script_text, hyp_words, tau=0.5):
    """Content-word recall of the script in a transcript (hyp_words: list of strings)."""
    sw = script_words(script_text)
    hyp_words = [d for d, _ in script_words(" ".join(hyp_words))]  # same clitic gluing as the script
    hk = [key(w) for w in hyp_words]
    res = match([key(b) for _, b in sw], hk, tau)
    content = [k for k, (_, b) in enumerate(sw) if is_content(b)]
    hit = [k for k in content if res[k][1] is not None]
    used = {j for _, span in res if span for j in range(span[0], span[1] + 1)}
    return {"recall": len(hit) / len(content), "precision": len(used) / max(1, len(hyp_words)),
            "missed": [sw[k][0] for k in content if res[k][1] is None], "res": res, "words": sw}

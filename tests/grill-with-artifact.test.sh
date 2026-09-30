#!/usr/bin/env bash
# grill-with-artifact's one seam: the round-data shape between a session and the
# fixed page. The page's script must parse; each sample round (questions, a
# carried question, closing) must match the shape `round-data.md` documents,
# figures holding only the figure style contract's classes; and the page, run
# headless over those samples and a click path, must read and write only the
# shape's fields. Reads are recorded through proxies, so the assertion is what
# crosses the seam, not how the page builds its DOM. Reaches no host; needs
# `node`, which the gate's Prettier already needs.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

command -v node >/dev/null || { echo "FAIL grill-with-artifact: node not on PATH" >&2; exit 1; }

out=$(node - skills/grill-with-artifact tests/fixtures/grill-with-artifact 2>&1 <<'JS'
const fs = require('fs'), vm = require('vm'), path = require('path');
const [skill, fx] = process.argv.slice(2);
const say = (...a) => console.log(a.join(' '));
const read = f => { try { return fs.readFileSync(f, 'utf8'); } catch { say('missing', f); process.exit(0); } };

const html = read(path.join(skill, 'page.html'));
const shapeDoc = read(path.join(skill, 'round-data.md'));
const sample = n => JSON.parse(read(path.join(fx, n + '.json')));

// The documented shape: every table row whose first cell is a round./answers. path.
const shape = new Map();
for (const m of shapeDoc.matchAll(/^\| `((?:round|answers)\.[^`]+)` \| [^|]+ \| (\w+) \|/gm)) shape.set(m[1], m[2]);
if (!shape.size) say('no field table in round-data.md');
const contract = [...shapeDoc.split('## Figure style contract')[1]?.matchAll(/^\| `([a-z-]+)` \|/gm) ?? []].map(m => m[1]);
if (!contract.length) say('no figure style contract table in round-data.md');

// Every object in a document with its path, `[]` standing for an array element.
function objects(v, p, acc = []) {
  if (Array.isArray(v)) v.forEach(x => objects(x, p + '[]', acc));
  else if (v && typeof v === 'object') { acc.push([p, v]); for (const k of Object.keys(v)) objects(v[k], p + '.' + k, acc); }
  return acc;
}
function checkShape(doc, root, label) {
  const all = objects(doc, root);
  for (const [p, o] of all) for (const k of Object.keys(o)) if (!shape.has(p + '.' + k)) say(label, 'has an undocumented field', p + '.' + k);
  for (const [f, req] of shape) {
    if (!f.startsWith(root + '.') || req === 'no') continue;
    const parent = f.slice(0, f.lastIndexOf('.')), key = f.slice(f.lastIndexOf('.') + 1);
    for (const [p, o] of all) if (p === parent && !(key in o) && ['yes', doc.kind, o.reason].includes(req)) say(label, 'lacks required field', f);
  }
}
function figureProblems(doc) {
  const out = [], svgs = [doc.treeSvg, ...(doc.questions ?? []).map(q => q.figureSvg)].filter(Boolean);
  for (const s of svgs) {
    for (const m of s.matchAll(/class=(["'])(.*?)\1/g)) for (const c of m[2].split(/\s+/)) if (c && !contract.includes(c)) out.push('figure uses a class outside the contract: ' + c);
    for (const m of s.matchAll(/\s(fill|stroke|style)=/g)) out.push('figure carries its own colour: ' + m[1]);
  }
  return out;
}
const styles = (css, c) => new RegExp('\\.' + c + '(?![\\w-])').test(css);
// The checkers themselves, on inputs they must refuse.
if (!figureProblems({ treeSvg: "<svg><g class='rogue'></g></svg>" }).length) say('figure check passes a single-quoted class');
if (styles('.hot-x { }', 'hot')) say('style check counts .hot-x as styling .hot');

const rounds = { questions: sample('round-questions'), carried: sample('round-carried'), closing: sample('round-closing') };
for (const [k, d] of Object.entries(rounds)) { checkShape(d, 'round', 'sample ' + k); for (const p of figureProblems(d)) say('sample ' + k, p); }

// The page: one script, one {{TOPIC}} placeholder in its title, a rule for every contract class.
const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]);
if (scripts.length !== 1) say('page has', scripts.length, 'inline scripts, want 1');
const src = scripts[0] ?? '';
try { new vm.Script(src, { filename: 'page.html' }); } catch (e) { say('page script does not parse:', e.message); process.exit(0); }
if (!/<title>\{\{TOPIC\}\}<\/title>/.test(html) || html.split('{{TOPIC}}').length !== 2) say('page lacks exactly one <title>{{TOPIC}}</title>');
for (const c of contract) if (!styles(html.split('<script>')[0], c)) say('page styles no .' + c);

// Run the page headless: no document, so it boots nothing and exposes its core.
const ctx = vm.createContext({ console });
vm.runInContext(src + '\n;globalThis.__page = { newState, setRounds, setAnswers, view, ACT, answersDoc, answersText };', ctx);
const P = ctx.__page;
const seen = new Set();
function watch(v, p) {
  if (!v || typeof v !== 'object') return v;
  return new Proxy(v, { get(t, k, r) {
    if (typeof k === 'symbol') return Reflect.get(t, k, r);
    if (Array.isArray(t)) return /^\d+$/.test(k) ? watch(t[k], p + '[]') : Reflect.get(t, k, r);
    seen.add(p + '.' + k);
    return watch(t[k], p + '.' + k);
  } });
}
const clone = o => JSON.parse(JSON.stringify(o));
const W = d => watch(clone(d), 'round');
function session(docs, answered = []) {
  const S = P.newState('Stale claims in ship');
  P.setRounds(S, docs.map(W));
  P.setAnswers(S, answered.map(a => watch(a, 'answers')));
  P.view(S);
  return S;
}
function checkAnswers(doc, label) {
  checkShape(doc, 'answers', label);
  if (typeof doc.submittedAt !== 'string' || isNaN(Date.parse(doc.submittedAt))) say(label, 'submittedAt is not an ISO time');
}

// A: round 1 open. Pick, Other with text, a comment, then read the answers back.
let S = session([rounds.questions]);
P.ACT.pick(S, { q: 'Q1', o: 'b' });
P.ACT.pick(S, { q: 'Q2', o: 'other' });
P.ACT.field(S, { q: 'Q2', field: 'other', value: 'On both' });
P.ACT.field(S, { q: 'Q1', field: 'comment', value: 'only for now' });
let A = P.answersDoc(S);
checkAnswers(A, 'answers A');
if (JSON.stringify(A.answers.map(a => a.choice)) !== '["b","other"]') say('answers A: choices', JSON.stringify(A.answers.map(a => a.choice)));
if (!/Q2: Other: On both/.test(P.answersText(S))) say('answers A: text lacks the Other answer');

// B: a carried round opens alone. Defer one, take the remaining recommendation, reopen a settled answer.
S = session([rounds.carried]);
P.ACT.pick(S, { q: 'Q1', o: 'defer' });
P.ACT.all(S);
P.ACT.reopen(S, { id: 'R2·Q1' });
A = P.answersDoc(S);
checkAnswers(A, 'answers B');
if (JSON.stringify(A.answers.map(a => a.choice)) !== '["defer","a"]') say('answers B: choices', JSON.stringify(A.answers.map(a => a.choice)));
if (JSON.stringify(A.reopen) !== '["R2·Q1"]') say('answers B: reopen', JSON.stringify(A.reopen));

// C: the closing round after a submitted round 3. Confirm, and a Not yet with its comment.
S = session([rounds.carried, rounds.closing], [{ round: 3, submittedAt: '2026-09-30T12:00:00Z', answers: [], reopen: [] }]);
P.ACT.closing(S, { choice: 'confirm' });
A = P.answersDoc(S);
checkAnswers(A, 'answers C');
if (A.answers.length !== 1 || A.answers[0].id !== 'closing' || A.answers[0].choice !== 'confirm') say('answers C:', JSON.stringify(A.answers));
P.ACT.closing(S, { choice: 'not-yet' });
P.ACT.field(S, { q: 'closing', field: 'comment', value: 'the notice text' });
if (P.answersDoc(S).answers[0].comment !== 'the notice text') say('answers C: Not yet lost its comment');

// D: a round whose answers are saved takes no more edits, and its text claims no save.
S = session([rounds.questions]);
S.status = 'saved';
P.ACT.pick(S, { q: 'Q1', o: 'a' });
if (P.answersDoc(S).answers[0].choice !== null) say('answers D: a saved round took an edit');
if (/saved/i.test(P.answersText(S).split('\n')[0])) say('answers D: the text header claims a save');

// E: counts agree with their nouns, one and many.
const one = clone(rounds.questions); one.questions = one.questions.slice(0, 1);
const tally = clone(rounds.carried); tally.settled = ['rec', 'rec', 'pick'].map((how, i) => ({ ...tally.settled[0], id: 'R2·Q' + (i + 1), how }));
if (!/open · 1 question</.test(P.view(session([one])))) say('view E: one question is not counted as one');
if (!/2 recommendations, 1 your pick</.test(P.view(session([tally])))) say('view E: settled counts misread');

// Every read the page made is a documented field, and it read the fields it renders.
for (const p of seen) if (!shape.has(p)) say('page reads an undocumented field', p);
for (const p of ['round.treeSvg', 'round.questions[].options[].detail', 'round.questions[].carriedFrom.earlier', 'round.settled[].how', 'round.docsWritten[].summary', 'round.summary[].text', 'answers.round'])
  if (!seen.has(p)) say('page never reads', p);
JS
)
check "the page and the samples hold to the round-data shape" "" "$out"

finish

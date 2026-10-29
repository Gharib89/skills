// Maintainer only: measure each narrator's speaking rate and pause on fixed
// texts and write them into narrators.json, where a script budgets scene
// characters.
//
//   node maintainer/calibrate-rates.mjs <language> [--all] [--file narrators.json] [id ...]
//
// Resumable: narrators.json is written after each narrator, a narrator that
// already has a numeric rate is skipped unless --all, and ids name the narrators
// of the language to calibrate, none meaning every one. A new narrator carries
// rate and pause null until calibrated, and a script naming it is refused.
// Needs the voice rows installed (`node scripts/setup.mjs install`); a Gemini
// narrator needs its key and spends its quota, so a quota stop leaves what was
// written and the next run goes on from the narrator it stopped at. The rate
// is spoken characters (`chars` in scripts/lib/length.mjs) per second of
// speech, each sentence timed from its first word's start to its last word's
// end; the pause a sentence is the audio's seconds less its speech, over its
// sentences, because a voiced scene carries the silence between its sentences
// and around each call.
// Both pool every text of the language. A narrator not yet calibrated this way
// carries pause 0 and a rate over its aligned span, first word to last, silence
// between sentences included, the same budget: elevenlabs-george. Its rate is
// converted, not measured: 3.07 words a second times 4.36, the English texts'
// characters a word (#783).
//
// The Gemini Egyptian voice list, probed 2026-10-28 with
// `GET https://generativelanguage.googleapis.com/v1beta/voices?languageCode=ar-EG`
// (paged by `next_page_token`): 92 voices, 90 of them beyond the two first
// narrators, each now a narrators.json entry.
// stdout: `calibrate <id> text <k>: <rate> chars/s, <pause> s a sentence` per
//         text, then `calibrate <id>: <rate> chars/s, <pause> s a sentence`,
//         the values written, per narrator calibrated, or
//         `calibrate <id>: skipped, already calibrated (--all measures it
//         again)` per narrator skipped
// stderr: `calibrate: stopped at <id>: <why>` when synthesis or alignment fails
// exit:   0 every narrator asked for calibrated or skipped · 1 synthesis or
//         alignment failed, the narrators before it kept · 2 usage
import fs from "node:fs";
import path from "node:path";
import { chars, sentences } from "../scripts/lib/length.mjs";
import { parseNarrators } from "../scripts/lib/narrators.mjs";
import { loadBackend, skill, toolPaths } from "../scripts/lib/tools.mjs";
import { align } from "../scripts/voice/align.mjs";

// Narration in the house register: technical terms, names, numbers
// spelled out, and sentences of the lengths a script carries.
const TEXTS = {
  en: [
    "When a browser asks for a page, the server can attach a caching header. " +
      "A max age of three thousand six hundred tells the browser to reuse its copy for one hour. " +
      "After that, the browser sends the ETag back and asks if anything changed. " +
      "If nothing did, the server answers three oh four, and no body travels at all.",
    "Linus Torvalds wrote Git in two thousand five to manage the Linux kernel. " +
      "A rebase replays your commits on top of the latest main branch. " +
      "Each commit gets a new SHA. " +
      "So the history reads as one straight line. " +
      "If two commits touch the same lines, Git stops and asks you to resolve the conflict by hand.",
    "Kubernetes runs your containers across a cluster of nodes. " +
      "You describe a Deployment in YAML, with three replicas and a readiness probe on port eight thousand eighty. " +
      "The scheduler places each Pod, and the kubelet on that node starts it. " +
      "When a node fails, the controller notices within forty seconds and starts a replacement somewhere else.",
    "OAuth two lets an app act for you without ever seeing your password. " +
      "The app sends you to the provider, say GitHub or Google. " +
      "There you sign in and approve the scopes. " +
      "The provider sends back a short code, which the app trades for an access token. " +
      "That token expires after about sixty minutes, and a refresh token gets a new one.",
  ],
  // Egyptian Arabic, English terms kept in Latin letters as a script writes
  // them: the workflow, then the narrations of two Arabic explainer runs, one
  // on pull requests and one on a downloads tidier.
  ar: [
    "كل pull request بيبدأ بمشكلة حد كتبها في issue. " +
      "الـ agent بيقرا الـ issue، وبيعمل branch جديد، وبيكتب التغيير مع الاختبارات بتاعته. " +
      "بعد كده بيشغل الـ CI، وبيفتح الـ pull request، وبيستنى الـ review. " +
      "لما الفحوصات تعدي والمراجعين يوافقوا، التغيير بيتعمل له merge، والـ issue بتتقفل لوحدها. " +
      "والموضوع كله بياخد ساعة أو اتنين بس، ومحدش محتاج يراجع كل خطوة بإيده.",

    "مين يقدر يغيّر في main على كيفه؟ ولا حد! كل تغيير لازم يعدّي على pull request، ومحدش بيرفع على main مباشرة. خلّينا نشوف الرحلة دي بسرعة. " +
      "الـ pull request ببساطة هو المكان اللي التغيير الواحد بيعيش فيه. فيه الـ diff بتاعه، ونتيجة الـ CI، والمراجعة بتاعته. يعني كل حاجة عن التغيير في مكان واحد. " +
      "تبدأ بـ branch من main لتغيير واحد، وتعمل commit وpush. وتفتح pull request. بعدها CI يشغّل الاختبارات، وأي فشل بيمنع الدمج. وبعدين مراجع يقرأ التغيير ويوافق، فيتدمج وبيتمسح الـ branch. " +
      "نلخّص: branch، وpull request، وCI يختبر، ومراجع يوافق، وبعدين merge. CI يمسك الاختبار المكسور قبل ما ينزل. والمراجعة تمسك اللي الاختبار مايقدرش يمسكه، زي اسم مش واضح أو حالة ناقصة. " +
      "يبقى القاعدة بسيطة: ولا تغيير على main من غير pull request. اختبار يمسك الغلط، ومراجع يمسك اللي الاختبار فاته، وكل ده في مكان واحد. يالا نفتح أول pull request.",
    "تخيل إن فولدر التحميلات بتاعك بقى مترتب لوحده من غير ما تعمل حاجة خالص. الأداة دي اسمها tidy، وبتحافظ على فولدر التحميلات مترتب طول الوقت، لو شغلتها مرة كل يوم. " +
      "بتشتغل مرة في اليوم، وبتوزع كل ملف على فولدر حسب نوعه. الأنواع هي الصور والمستندات والأرشيفات وملفات التثبيت. تعالوا نشوف دلوقتي أهم الحاجات اللي بيعملها بالتفصيل يا جماعة. " +
      "أي ملف أقدم من تلاتين يوم بيتنقل لفولدر old، فالمستوى الأعلى مفيهوش غير الجديد. وأي ملفين ليهم نفس البايتات بيتحفظ منهم نسخة واحدة، والتانية بتروح trash. و trash بيتفضى بعد أسبوع. " +
      "tidy بيرتب الملفات حسب نوعها، وبينقل القديم، وبيشيل المكرر. ولو خايف، شغله بالأمر dry-run وهو هيطبع كل نقلة من غير ما يلمس حاجة. وكده تبقى متأكد قبل أي تغيير. " +
      "ومفيش حاجة بتسيب جهازك، لأن tidy بيقرا أسماء الملفات وأحجامها وبايتاتها بس. ومبيفتحش أي اتصال بالشبكة خالص، يعني خصوصيتك محفوظة. جربه النهاردة وسيب فولدر التحميلات يرتب نفسه.",
  ],
};

const usage = (why) => {
  console.error(
    `${why ? `calibrate: ${why}\n` : ""}usage: node calibrate-rates.mjs <${Object.keys(TEXTS).join("|")}> [--all] [--file narrators.json] [id ...]`,
  );
  process.exit(2);
};
const args = process.argv.slice(2);
const language = args.shift();
let all = false;
let file = path.join(skill, "narrators.json");
const ids = [];
while (args.length) {
  const a = args.shift();
  if (a === "--all") all = true;
  else if (a === "--file") file = args.shift() ?? usage("--file needs a path");
  else if (a.startsWith("--")) usage(`no option ${a}`);
  else ids.push(a);
}
if (!TEXTS[language]) usage();

// The narrators as every reader sees them, and the file's own entries, which
// take the rate and pause and are written back over the defaults block.
const body = fs.readFileSync(file, "utf8");
const seen = parseNarrators(body);
const doc = JSON.parse(body);
const ofLanguage = seen.filter((n) => n.language === language);
for (const id of ids)
  if (!ofLanguage.some((n) => n.id === id))
    usage(`no ${language} narrator ${id}`);
const tools = toolPaths();
const backend = await loadBackend();
const ctc = await backend.aligner({ language, tools });
const r2 = (x) => +x.toFixed(2);
let stoppedAt;
try {
  for (const n of ofLanguage.filter((n) => !ids.length || ids.includes(n.id))) {
    if (!all && Number.isFinite(n.rate)) {
      console.log(
        `calibrate ${n.id}: skipped, already calibrated (--all measures it again)`,
      );
      continue;
    }
    stoppedAt = n.id;
    const sum = { chars: 0, speech: 0, silence: 0, sentences: 0 };
    for (const [k, text] of TEXTS[language].entries()) {
      const said = sentences(text).map((s) => s.split(/\s+/));
      const { samples, sampleRate } = await backend.synthesize({
        text,
        narrator: n,
        language,
        tools,
      });
      const timed = (await align(samples, sampleRate, said.flat(), ctc)).words;
      let first = 0;
      let speech = 0;
      for (const s of said) {
        speech += timed[first + s.length - 1].end - timed[first].start;
        first += s.length;
      }
      const t = {
        chars: chars(text),
        speech,
        silence: samples.length / sampleRate - speech,
        sentences: said.length,
      };
      for (const key in sum) sum[key] += t[key];
      console.log(
        `calibrate ${n.id} text ${k + 1}: ${r2(t.chars / t.speech)} chars/s, ${r2(t.silence / t.sentences)} s a sentence`,
      );
    }
    n.rate = r2(sum.chars / sum.speech);
    n.pause = r2(sum.silence / sum.sentences);
    Object.assign(doc.narrators[seen.indexOf(n)], {
      rate: n.rate,
      pause: n.pause,
    });
    // Written now, not at the end: a later narrator's quota stop keeps this one.
    fs.writeFileSync(file, JSON.stringify(doc, null, 2) + "\n");
    console.log(
      `calibrate ${n.id}: ${n.rate} chars/s, ${n.pause} s a sentence`,
    );
  }
} catch (e) {
  console.error(`calibrate: stopped at ${stoppedAt}: ${e.message}`);
  process.exit(1);
}

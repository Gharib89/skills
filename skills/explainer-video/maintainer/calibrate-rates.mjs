// Maintainer only: measure each narrator's speaking rate and pause on fixed
// texts and write them into narrators.json, where the script stage budgets
// scene words.
//
//   node maintainer/calibrate-rates.mjs <language> [narrators.json]
//
// Needs the voice rows installed (`node scripts/setup.mjs install`). The rate
// is words per second of speech, each sentence timed from its first word's
// start to its last word's end; the pause a sentence is the audio's seconds
// less its speech, over its sentences, because a voiced scene carries each
// sentence's lead and tail silence (Kokoro voices one sentence per inference).
// Both pool every text of the language. A narrator not yet calibrated this way
// carries pause 0 and a rate over its whole audio, the same budget.
// stdout: `calibrate <id> text <k>: <rate> words/s, <pause> s a sentence` per
//         text, then `calibrate <id>: <rate> words/s, <pause> s a sentence`,
//         the values written, per narrator of that language
// exit:   0 written · 1 synthesis or alignment failed · 2 usage
import fs from "node:fs";
import path from "node:path";
import { sentences as split } from "../scripts/lib/length.mjs";
import { loadBackend, skill, toolPaths } from "../scripts/lib/tools.mjs";
import { align } from "../scripts/voice/align.mjs";

// Explainer narration in the house register: technical terms, names, numbers
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
  // Egyptian Arabic, English terms kept in Latin letters as the script stage
  // writes them: the workflow, then the narrations of two Arabic explainer
  // runs, one on pull requests and one on a downloads tidier.
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

const [language, file = path.join(skill, "narrators.json"), ...rest] =
  process.argv.slice(2);
if (!TEXTS[language] || rest.length) {
  console.error(
    `usage: node calibrate-rates.mjs <${Object.keys(TEXTS).join("|")}> [narrators.json]`,
  );
  process.exit(2);
}

const doc = JSON.parse(fs.readFileSync(file, "utf8"));
const tools = toolPaths();
const backend = await loadBackend();
const ctc = await backend.aligner({ language, tools });
const r2 = (x) => +x.toFixed(2);
try {
  for (const n of doc.narrators.filter((n) => n.language === language)) {
    const sum = { words: 0, speech: 0, silence: 0, sentences: 0 };
    for (const [k, text] of TEXTS[language].entries()) {
      const sentences = split(text).map((s) => s.split(/\s+/));
      const { samples, sampleRate } = await backend.synthesize({
        text,
        narrator: n,
        language,
        tools,
      });
      const timed = (await align(samples, sampleRate, sentences.flat(), ctc))
        .words;
      let first = 0;
      let speech = 0;
      for (const s of sentences) {
        speech += timed[first + s.length - 1].end - timed[first].start;
        first += s.length;
      }
      const t = {
        words: timed.length,
        speech,
        silence: samples.length / sampleRate - speech,
        sentences: sentences.length,
      };
      for (const key in sum) sum[key] += t[key];
      console.log(
        `calibrate ${n.id} text ${k + 1}: ${r2(t.words / t.speech)} words/s, ${r2(t.silence / t.sentences)} s a sentence`,
      );
    }
    n.rate = r2(sum.words / sum.speech);
    n.pause = r2(sum.silence / sum.sentences);
    console.log(
      `calibrate ${n.id}: ${n.rate} words/s, ${n.pause} s a sentence`,
    );
  }
} catch (e) {
  console.error(`calibrate: ${e.message}`);
  process.exit(1);
}
fs.writeFileSync(file, JSON.stringify(doc, null, 2) + "\n");

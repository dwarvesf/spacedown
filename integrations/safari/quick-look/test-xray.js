// test-xray.js: the Writing X-ray lens (Resources/xray.js). Owned by the X-ray node;
// docs/contract-r1.md. Run: node test-xray.js  ->  exit 0 + "xray: PASS".
// Dashes are built at runtime (a write hook rewrites literal ones in source files).
const { loadCore } = require("./load-core");

let fail = 0;
function check(name, cond) {
  if (cond) { console.log("  ok: " + name); } else { console.error("  FAIL: " + name); fail++; }
}

const EM = String.fromCharCode(0x2014);
const EN = String.fromCharCode(0x2013);
const SD = loadCore().SD;
const xray = SD.plugin("xray");

// Settings with every rule off except the ones named.
function only(...rules) {
  const off = { xrayDashes: false, xrayLongSentences: false, xrayFillers: false, xrayTicketIds: false };
  rules.forEach((r) => { off[r] = true; });
  return off;
}
const body = (src, cfg) => SD.render(src, cfg).body;
const marks = (html, rule) => (html.match(new RegExp('class="sd-xr sd-xr-' + rule + '"', "g")) || []).length;
const markText = (html, rule) => {
  const out = [];
  const re = new RegExp('<span class="sd-xr sd-xr-' + rule + '"[^>]*>([^<]*)</span>', "g");
  let m;
  while ((m = re.exec(html)) !== null) out.push(m[1]);
  return out;
};
const sentence = (n, word = "word") => (word + " ").repeat(n).trim() + ".";

check("xray registers with SD, order 100", !!xray && xray.order === 100 && SD.plugins().includes("xray"));

// The core must call the lens on every render, with the validated settings.
const seen = [];
const transform = xray.transform;
xray.transform = (html, cfg) => { seen.push(cfg); return transform(html, cfg); };
const out = SD.render("# T\n\nOne sentence.", { xraySentenceWords: 12 });
check("render calls the xray transform with its settings",
  seen.length === 1 && seen[0].xraySentenceWords === 12 && /<h1/.test(out.body));
xray.transform = transform;

// ---- Rule: dashes ----
{
  const src = "A " + EM + " B and C " + EN + " D, plus E&mdash;F.";
  const on = body(src, only("xrayDashes"));
  check("dashes: em, en and the &mdash; entity are marked", marks(on, "dash") === 3);
  check("dashes: the mark keeps the character and names the rule",
    markText(on, "dash")[0] === EM && /title="X-ray, em dash/.test(on) && /title="X-ray, en dash/.test(on));
  check("dashes: off means no marks", marks(body(src, only("xrayLongSentences")), "dash") === 0);
  check("dashes: a plain hyphen is not a dash", marks(body("well-known and a - b", only("xrayDashes")), "dash") === 0);
}

// ---- Rule: long sentences, and the word limit ----
{
  const s25 = sentence(25), s26 = sentence(26);
  check("long: exactly the limit is not marked", marks(body(s25, only("xrayLongSentences")), "long") === 0);
  check("long: one word over is marked, with the count in the title",
    /sd-xr-long" title="X-ray, long sentence: 26 words, limit 25"/.test(body(s26, only("xrayLongSentences"))));
  check("long: setting 40 lets 26 words pass", marks(body(s26, { ...only("xrayLongSentences"), xraySentenceWords: 40 }), "long") === 0);
  check("long: setting 8 marks 12 words", marks(body(sentence(12), { ...only("xrayLongSentences"), xraySentenceWords: 8 }), "long") === 1);
  check("long: off means no marks", marks(body(s26, only("xrayDashes")), "long") === 0);
  check("long: the sentence carries its word count for the tag", / data-sd-words="26">[^<]*\.<\/span>/.test(body(s26, only("xrayLongSentences"))));
  check("long: no count on a short sentence or with the rule off", !/data-sd-words/.test(body(s25, only("xrayLongSentences"))) &&
    !/data-sd-words/.test(body(s26, only("xrayDashes"))));
  const split = body("word ".repeat(12) + "**bold " + "word ".repeat(12) + "end**.", only("xrayLongSentences"));
  check("long: a sentence across bold gets one tag, after its last piece",
    (split.match(/data-sd-words/g) || []).length === 1 && /<\/strong><span[^>]* data-sd-words="26">\.<\/span><\/p>/.test(split));
  const two = sentence(30) + " Short one. " + sentence(30);
  check("long: only the long sentences are marked, each its own span",
    marks(body(two, only("xrayLongSentences")), "long") === 2);
  const abbr = "Use a tool, e.g. a hammer, vs. a saw, Dr. Smith said so, etc. " + "word ".repeat(10) + "end.";
  check("long: e.g., vs., Dr. and etc. do not split a sentence (one 26 word sentence, limit 25)",
    marks(body(abbr, only("xrayLongSentences")), "long") === 1);
  const inline = "word ".repeat(15) + "**bold" + " word".repeat(5) + "** and `code` [a link](http://x.test/a) " + "word ".repeat(5) + "end.";
  const il = body(inline, only("xrayLongSentences"));
  check("long: a sentence across bold, code and a link is marked in every text piece, code untouched",
    marks(il, "long") >= 4 && !/<code><span/.test(il) && /<code>code<\/code>/.test(il));
  check("long: separate paragraphs and list items never join into one sentence",
    marks(body("word ".repeat(15) + "\n\nword ".repeat(1) + "x ".repeat(14) + "\n\n- " + "w ".repeat(14), only("xrayLongSentences")), "long") === 0);
}

// ---- Rule: filler words ----
{
  const src = "It is Very good, really. Of Course it works, in order to ship. Every verybody, justice.";
  const on = body(src, only("xrayFillers"));
  const got = markText(on, "filler").map((t) => t.toLowerCase());
  check("fillers: whole words, phrases and any case", got.join("|") === "very|really|of course|in order to");
  check("fillers: no hit inside every, verybody or justice", !/>Every<|verybody<|justice</.test(markText(on, "filler").join("<")));
  check("fillers: off means no marks", marks(body(src, only("xrayDashes")), "filler") === 0);
  const custom = body("Please just ship, simply.", { ...only("xrayFillers"), xrayFillerWords: ["simply"] });
  check("fillers: the word list setting replaces the default", markText(custom, "filler").join() === "simply");
  check("fillers: an empty list marks nothing", marks(body(src, { ...only("xrayFillers"), xrayFillerWords: [] }), "filler") === 0);
  check("fillers: a regex character in a word is literal",
    markText(body("a (very) c++ b", { ...only("xrayFillers"), xrayFillerWords: ["c++", "(very)"] }), "filler").length === 2);
}

// ---- Rule: ticket and spec IDs ----
{
  const src = "See SPEC-421, ID-945 and ABC-123. Not UTF-8, SHA-256, abc-123 or x-1.";
  const on = body(src, only("xrayTicketIds"));
  check("tickets: SPEC-421, ID-945 and ABC-123 are marked, standards and lowercase are not",
    markText(on, "ticket").join("|") === "SPEC-421|ID-945|ABC-123");
  check("tickets: off means no marks", marks(body(src, only("xrayDashes")), "ticket") === 0);
}

// ---- Settings that name no rule, and all rules together ----
{
  const mixed = "Really " + EM + " SPEC-9 is " + sentence(30);
  const html = body(mixed, {});
  check("all rules on by default: one of each", marks(html, "dash") === 1 && marks(html, "filler") === 1 &&
    marks(html, "ticket") === 1 && marks(html, "long") >= 1);
  check("all rules off: the body is identical to a render with no plug-in output",
    body(mixed, only()) === body(mixed, only()).replace(/class="sd-xr/g, "x") && marks(body(mixed, only()), "dash") === 0);
  const stripped = html.replace(/<span class="sd-xr [^"]*" title="[^"]*"( data-sd-words="\d+")?>/g, "");
  const opens = (html.match(/<span class="sd-xr /g) || []).length;
  const closes = (html.match(/<\/span>/g) || []).length;
  check("marks nest: every opened span is closed", opens === closes);
  check("marks add no text: removing them restores the plain render",
    stripped.replace(/<\/span>/g, "") === body(mixed, only()).replace(/<\/span>/g, ""));
}

// ---- Prose only: code, pre, math, link targets ----
{
  const src = [
    "Really " + EM + " in prose. See SPEC-1.",
    "",
    "Inline `very SPEC-2 " + EM + "` code.",
    "",
    "```js",
    "// very really " + EM + " ABC-123 " + sentence(40),
    "```",
    "",
    "    indented SPEC-3 very " + EM,
    "",
    "[the doc](https://example.test/SPEC-4/very" + EM + "x) and <https://example.test/ID-77>",
    "",
    "Math $x " + EM + " y$ then.",
    "",
    "$$ a " + EM + " b $$"
  ].join("\n");
  const html = body(src, {});
  check("prose is marked (dash, filler, ticket)", marks(html, "dash") >= 1 && markText(html, "ticket").includes("SPEC-1"));
  check("inline code is untouched", /<code>very SPEC-2 /.test(html) && !/<code>[^<]*sd-xr/.test(html));
  const pre = (html.match(/<pre>[\s\S]*?<\/pre>/g) || []).join("");
  check("fenced and indented code blocks have no marks", pre.length > 0 && !/sd-xr/.test(pre));
  const katex = (html.match(/<span class="katex[\s\S]*?<\/annotation>/g) || []).join("");
  check("math has no marks", katex.length > 0 && !/sd-xr/.test(katex));
  check("link targets are untouched, link text is still prose",
    /href="https:\/\/example\.test\/SPEC-4\/very/.test(html) && /href="https:\/\/example\.test\/ID-77"/.test(html) &&
    !/href="[^"]*sd-xr/.test(html) && !/title="[^"]*sd-xr/.test(html));
  check("code block text survives byte for byte", /ABC-123 word word/.test(pre));
}

// ---- Vietnamese: diacritics never split a word ----
{
  const vi = "Tiếng Việt có nhiều dấu như ă â ê ô ơ ư và đ, nên một câu dài cần được đếm đúng từng từ một.";
  const n = vi.split(/\s+/).length;
  const cfg = { ...only("xrayLongSentences"), xraySentenceWords: 8 };
  const nfc = vi.normalize("NFC"), nfd = vi.normalize("NFD");
  const title = (h) => (/long sentence: (\d+) words/.exec(h) || [])[1];
  check("vietnamese: word count equals the space separated count (NFC)", +title(body(nfc, cfg)) === n);
  check("vietnamese: decomposed (NFD) text counts the same, no split on combining marks", +title(body(nfd, cfg)) === n);
  const filler = { ...only("xrayFillers"), xrayFillerWords: ["rất", "thực sự"] };
  const vf = body("Món này rất ngon, thực sự ngon. Còn sâu rất? Rất mà thực tế không.", filler);
  check("vietnamese: filler words and phrases found, whole word only",
    markText(vf, "filler").map((t) => t.toLowerCase()).join("|") === "rất|thực sự|rất|rất");
  check("vietnamese: a filler is not matched inside a longer word", marks(body("Phát triển rất, ratất.", filler), "filler") === 1);
  check("vietnamese: a sentence under the limit is not marked", marks(body("Xin chào các bạn.", cfg), "long") === 0);
}

// ---- HTML entities in prose ----
{
  const html = body("It's a \"very\" good don't & very <b>x</b> thing, 3.5 or 1,000 times " + sentence(10), only("xrayFillers", "xrayLongSentences"));
  check("entities: apostrophes and ampersands do not break the scan, markup is intact",
    markText(html, "filler").join("|") === "very|very" && /&amp;/.test(html) && /&quot;|"/.test(html));
  const counted = body("Don't stop, it's 3.5 or 1,000 now.", { ...only("xrayLongSentences"), xraySentenceWords: 8 });
  check("entities: a contraction and a decimal number are one word each (7 words, limit 8, not marked)", marks(counted, "long") === 0);
}

// ---- Chrome: checkbox, label, legend, css ----
{
  const on = SD.render("x", { xrayEnabled: true });
  const off = SD.render("x", { xrayEnabled: false });
  check("controls: hidden checkbox #sd-xray, checked when xrayEnabled",
    /<input type="checkbox" id="sd-xray" hidden checked>/.test(on.chrome) && /<input type="checkbox" id="sd-xray" hidden>/.test(off.chrome));
  check("controls: the checkbox comes before the toolbar (a sibling selector reaches the page)",
    on.chrome.indexOf('id="sd-xray"') < on.chrome.indexOf("sd-ql-toolbar"));
  check("toolbar: a label for the checkbox, with a legend of the active rules",
    /<label class="sd-xr-toggle" for="sd-xray"/.test(on.chrome) && /sd-xr-chip-dash/.test(on.chrome) &&
    /sd-xr-chip-long/.test(on.chrome) && /sd-xr-chip-filler/.test(on.chrome) && /sd-xr-chip-ticket/.test(on.chrome));
  check("toolbar: the title names the sentence limit", /over 25 words/.test(on.chrome) &&
    /over 40 words/.test(SD.render("x", { xraySentenceWords: 40 }).chrome));
  const some = SD.render("x", only("xrayDashes")).chrome;
  check("toolbar: the legend lists only the active rules", /chip-dash/.test(some) && !/chip-long|chip-filler|chip-ticket/.test(some));
  check("toolbar: with every rule off the label says so", /every rule is off/.test(SD.render("x", only()).chrome));
  check("css: marks show only under the checked checkbox, no :has()",
    /#sd-xray:checked ~ \* \.sd-xr-dash\{/.test(on.css) && /#sd-xray:checked ~ \* \.sd-xr-long\{/.test(on.css) &&
    /#sd-xray:checked ~ \* \.sd-xr-filler\{/.test(on.css) && /#sd-xray:checked ~ \* \.sd-xr-ticket\{/.test(on.css) &&
    !/:has\(/.test(on.css));
  check("css: unchecked marks take no pointer events (no tooltips while the lens is off)", /\.sd-xr\{pointer-events:none\}/.test(on.css));
  const longRule = (/#sd-xray:checked ~ \* \.sd-xr-long\{([^}]*)\}/.exec(on.css) || [])[1] || "";
  check("css: a long sentence is a dotted underline in its rule color, never a fill",
    /underline dotted var\(--sd-xr-longline\)/.test(longRule) && !/background/.test(longRule));
  check("css: the word-count tag is generated content, only under the checked checkbox",
    /#sd-xray:checked ~ \* \.sd-xr-long\[data-sd-words\]::after\{content:attr\(data-sd-words\) "w"/.test(on.css) &&
    !/(^|\n|\})\.sd-xr-long\[data-sd-words\]::after/.test(on.css));
  check("render output has no em or en dash characters", !(on.css + on.chrome + off.chrome).includes(EM) && !(on.css + on.chrome).includes(EN));
}

// ---- Colors: contrast and lightness, light and dark ----
{
  const css = SD.render("x", {}).css;
  const lin = (c) => { c /= 255; return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
  const lum = (hex) => {
    const n = parseInt(hex.slice(1), 16);
    return 0.2126 * lin(n >> 16) + 0.7152 * lin((n >> 8) & 255) + 0.0722 * lin(n & 255);
  };
  const contrast = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
  const lstar = (hex) => { const y = lum(hex); return y > 216 / 24389 ? 116 * Math.cbrt(y) - 16 : y * 24389 / 27; };
  const tokens = (block) => {
    const o = {}; let m; const re = /--sd-xr-([a-z]+):(#[0-9a-f]{6})/g;
    while ((m = re.exec(block)) !== null) o[m[1]] = m[2];
    return o;
  };
  const light = tokens(css.split("\n").filter((l) => /^:root\{--sd-xr/.test(l))[0] || "");
  const darkBlock = css.split("\n").filter((l) => /data-sd-appearance="dark"\]\{/.test(l))[0] || "";
  const dark = tokens(darkBlock);
  const media = tokens((/@media \(prefers-color-scheme:dark\)\{[^\n]*/.exec(css) || [""])[0]);
  const names = ["dash", "long", "ticket", "filler"];
  [["light", light], ["dark", dark]].forEach(([label, t]) => {
    check(label + ": ink and four fills are defined", !!t.ink && names.every((n) => !!t[n]));
    check(label + ": every fill has contrast 4.5 or more with its ink (lowest " +
      Math.min(...names.map((n) => contrast(t.ink, t[n]))).toFixed(1) + ")", names.every((n) => contrast(t.ink, t[n]) >= 4.5));
    const ls = names.map((n) => lstar(t[n])).sort((a, b) => a - b);
    const gaps = ls.slice(1).map((v, i) => v - ls[i]);
    check(label + ": the four fills differ in lightness by at least 6 L* points (smallest gap " + Math.min(...gaps).toFixed(1) + ")",
      Math.min(...gaps) >= 6);
  });
  check("dark: the system dark media block carries the same tokens as the forced dark one",
    names.every((n) => media[n] === dark[n]) && media.ink === dark.ink);
  check("dark: the light appearance override keeps the light tokens under a dark system", /:root:not\(\[data-sd-appearance="light"\]\)/.test(css));
  check("light fills are lighter than dark fills", names.every((n) => lstar(light[n]) > lstar(dark[n])));
}

// ---- Long document: speed ----
{
  const para = "This is really a plain sentence about nothing " + EM + " and SPEC-12 appears. " +
    "Another one follows, in order to fill the page, with a few more words. " + sentence(30) + "\n\n";
  let src = "";
  while (src.split(/\s+/).length < 2000) src += para;
  const words = src.split(/\s+/).length;
  const plain = body(src, only());
  const cfg = SD.config({});
  const warm = xray.transform(plain, cfg); // warm up
  const times = [];
  for (let i = 0; i < 7; i++) {
    const t0 = process.hrtime.bigint();
    xray.transform(plain, cfg);
    times.push(Number(process.hrtime.bigint() - t0) / 1e6);
  }
  times.sort((a, b) => a - b);
  const med = times[3];
  check("speed: " + words + " words marked in " + med.toFixed(1) + " ms median (limit 50)", med < 50 && words >= 2000 && marks(warm, "dash") > 20 && marks(warm, "ticket") > 20 && marks(warm, "long") > 20);
}

check("no hook errors", SD.errors.length === 0);

if (fail) { console.error("\nxray: " + fail + " FAILED"); process.exit(1); }
console.log("\nxray: PASS");

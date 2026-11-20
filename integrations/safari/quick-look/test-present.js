// test-present.js: Present mode (Resources/present.js). Owned by the Present node;
// docs/contract-r1.md. Run: node test-present.js  ->  exit 0 + "present: PASS".
const { loadCore } = require("./load-core");

let fail = 0;
function check(name, cond) {
  if (cond) { console.log("  ok: " + name); } else { console.error("  FAIL: " + name); fail++; }
}

const WRAP = /<section class="sd-slide[^"]*" data-slide="\d+">|<\/section>/g;
const unwrap = (html) => html.replace(WRAP, "");
const slidesOf = (html) => {
  const out = [];
  const re = /<section class="(sd-slide[^"]*)" data-slide="(\d+)">([\s\S]*?)<\/section>/g;
  let m;
  while ((m = re.exec(html))) out.push({ cls: m[1], n: +m[2], html: m[3] });
  return out;
};
const headings = (s) => (s.html.match(/<h[1-6][^>]*>[\s\S]*?<\/h[1-6]>/g) || []).map((h) => h.replace(/<[^>]+>/g, ""));

// ---- registration and the host wiring (kept from the stub) ----
const ctx = loadCore();
const SD = ctx.SD;
const present = SD.plugin("present");
check("present registers with SD, after xray",
  !!present && SD.plugins().indexOf("present") > SD.plugins().indexOf("xray"));

let rendered = 0;
const transform = present.transform;
present.transform = (html, cfg) => { rendered++; return transform(html, cfg); };
SD.render("## One\n\n---\n\n## Two");
check("render calls the present transform", rendered === 1);
present.transform = transform;

const keys = [];
const key = present.key;
present.key = (ev, cfg) => { keys.push(ev.key); return key(ev, cfg); };
const listeners = {};
SD.boot({ addEventListener: (t, f) => { listeners[t] = f; }, defaultView: null });
listeners.keydown({ key: "p", target: { tagName: "BODY" }, preventDefault() {} });
check("boot routes the P key to present", keys.includes("p"));
present.key = key;

// ---- split rules ----
const body = (md) => loadCore().SD.render(md).body;

let s = slidesOf(body("# Title\n\nIntro.\n\n## One\n\nA\n\n## Two\n\nB"));
check("H2 splits: title slide plus one per H2", s.length === 3);
check("title slide holds the H1 and the intro", headings(s[0]).join() === "Title" && /Intro/.test(s[0].html));
check("title slide is marked sd-title, the others are not",
  s[0].cls === "sd-slide sd-title" && s[1].cls === "sd-slide" && s[2].cls === "sd-slide");
check("each H2 opens its slide", headings(s[1]).join() === "One" && headings(s[2]).join() === "Two");
check("slides are numbered from 1", s.map((x) => x.n).join() === "1,2,3");

s = slidesOf(body("# Title\n\nIntro.\n\n---\n\nSecond\n\n---\n\nThird"));
check("--- splits too", s.length === 3);
check("the break stays with the slide it ends", /<hr/.test(s[0].html) && /<hr/.test(s[1].html) && !/<hr/.test(s[2].html));
check("text after a break opens the next slide", /Second/.test(s[1].html) && /Third/.test(s[2].html));

s = slidesOf(body("# Title\n\nA\n\n## One\n\nB\n\n---\n\nC\n\n## Two\n\nD"));
check("H2 and --- mix: four slides", s.length === 4);

s = slidesOf(body("Just a paragraph.\n\nAnd another, with no headings.\n\n- a list"));
check("no headings: one slide", s.length === 1 && /another/.test(s[0].html) && /<li>/.test(s[0].html));
check("a one-slide document without an H1 is not a title slide", s[0].cls === "sd-slide");

s = slidesOf(body("## First\n\nA\n\n## Second\n\nB"));
check("a document that opens on an H2 has no title slide", s.length === 2 && !/sd-title/.test(s[0].cls));
check("H3 and deeper do not split", slidesOf(body("# T\n\n### a\n\n#### b\n\ntext")).length === 1);

s = slidesOf(body("# T\n\nx\n\n---\n\n---\n\n---\n\n## After"));
check("consecutive breaks make no empty slides", s.length === 2);
check("every slide has content", s.every((x) => x.html.replace(/<hr[^>]*>/g, "").trim() !== ""));

s = slidesOf(body("---\ntitle: Doc\nauthor: Me\n---\n\n# Head\n\nBody\n\n## Next\n\nMore"));
check("frontmatter table sits in the title slide", s.length === 2 && /sd-frontmatter/.test(s[0].html) && /Head/.test(s[0].html));

s = slidesOf(body("# T\n\n> ## Quoted heading\n>\n> ---\n>\n> still quoted\n\n<details><summary>More</summary>\n\n## Inside\n\n---\n\ntext\n</details>\n\ntail"));
check("an H2 or --- inside a blockquote or details does not split", s.length === 1);

s = slidesOf(body("# T\n\n```md\n## not a heading\n---\n```\n\n    ## indented code\n\nafter"));
check("H2 and --- inside a code block do not split", s.length === 1);

s = slidesOf(body("# T\n\nInline $x^2$ here.\n\n## Math\n\n$$\\frac{a}{b}$$\n\n```js\nconst a = 1;\n```\n\nEnd"));
check("math and code inside slides render as they did", s.length === 2 && /katex/.test(s[0].html + s[1].html) && /hljs|<code/.test(s[1].html));

// ---- the unchecked page reads exactly as before ----
const base = loadCore();
base.SD.register({ id: "present", order: 200, transform: (h) => h });
const doc1 = [
  "---\ntitle: Doc\n---\n\n# Title\n\nIntro with `code` and $e=mc^2$.\n\n## One\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n---\n\n```js\nconst x = 1;\n```\n\n## Two\n\n- [ ] task\n- item\n\n> [!NOTE]\n> callout\n\n<details><summary>d</summary>\n\nhidden\n</details>",
  "no headings, only text",
  "## Starts on a heading\n\ntext\n\n---\n\n## Another",
  ""
];
doc1.forEach((md, i) => {
  const plain = base.SD.render(md).body;
  const slid = loadCore().SD.render(md).body;
  check("doc " + (i + 1) + ": without the wrappers the body is byte for byte the same", unwrap(slid) === plain);
});
check("an empty document stays empty", loadCore().SD.render("").body === base.SD.render("").body);
check("only slide wrappers were added",
  (loadCore().SD.render(doc1[0]).body.match(/<section/g) || []).length === slidesOf(loadCore().SD.render(doc1[0]).body).length);

// ---- render-time layer: checkbox, label, css ----
const page = loadCore().SD.render("# T\n\n## A\n\nx");
check("controls: a hidden checkbox #sd-present, ahead of the content",
  /<input type="checkbox" id="sd-present" hidden>/.test(page.chrome) &&
  page.chrome.indexOf("sd-present") < page.chrome.indexOf("sd-ql-toolbar"));
check("toolbar: a Present label for the checkbox",
  /<label[^>]*for="sd-present"[^>]*>[\s\S]*Present[\s\S]*<\/label>/.test(page.chrome));
check("css: scroll snapping on, slides at least one screen tall",
  /scroll-snap-type:y mandatory/.test(page.css) && /min-height:100vh/.test(page.css) &&
  /scroll-snap-align:start/.test(page.css));
check("css: the checked state switches slides on, by sibling selector",
  /#sd-present:checked ~ \.sd-slide\{/.test(page.css));
check("css: no :has(), the sibling selector alone toggles the slides", !/:has\(/.test(page.css));
check("css: off, slide children keep the reading page's body-child measure, rhythm and phone table scroll",
  /#sd-present:not\(:checked\) ~ \.sd-slide > p,/.test(page.css) &&
  /#sd-present:not\(:checked\) ~ \.sd-slide > hr\{max-width:var\(--sd-measure\)\}/.test(page.css) &&
  /#sd-present:not\(:checked\) ~ \.sd-slide > h2\{margin-top:32px\}/.test(page.css) &&
  /max-width:600px\)\{#sd-present:not\(:checked\) ~ \.sd-slide > table:not\(\.sd-frontmatter\)\{display:block;overflow-x:auto/.test(page.css));
check("css: no em or en dash", !/[\u2013\u2014]/.test(page.css + page.chrome));
check("css: slide layout is screen only, so print stays the reading page",
  /@media screen\{#sd-present:checked ~ \.sd-slide\{/.test(page.css) &&
  !/@media print/.test(SD.plugin("present").css({})));
check("css: before the checkbox is checked, no slide rule applies",
  page.css.split("@media screen{")[0].indexOf(".sd-slide") === -1);
check("css: large type, centered", /font-size:calc\(var\(--ql-size,18px\)\*1\.6\)/.test(page.css) &&
  /justify-content:center/.test(page.css) && /text-align:center/.test(page.css));

// ---- page-time layer: a fake document ----
function makeDoc(slideCount, withBox) {
  const state = { scrollY: 0, scrolledTo: [] };
  const slides = [];
  for (let i = 0; i < slideCount; i++) {
    slides.push({
      getBoundingClientRect: () => ({ top: i * 700 - state.scrollY }),
      scrollIntoView() { state.scrollY = i * 700; state.scrolledTo.push(i); }
    });
  }
  const box = { id: "sd-present", checked: false };
  const count = { textContent: "" };
  const listeners = {};
  const win = { listeners: {}, addEventListener(t, f) { (this.listeners[t] = this.listeners[t] || []).push(f); } };
  const created = [];
  const doc = {
    state, slides, box, count, listeners, win,
    body: { insertBefore(el) { created.push(el); doc.box = el; } },
    defaultView: win,
    addEventListener(t, f) { listeners[t] = f; },
    getElementById(id) { return id === "sd-present" ? (withBox === false ? doc.created : box) : null; },
    querySelector(sel) { return sel === ".sd-present-count" ? count : null; },
    querySelectorAll(sel) { return sel === ".sd-slide" ? slides : []; },
    createElement() { const el = { attrs: {}, checked: false, setAttribute(k, v) { this.attrs[k] = v; } }; doc.created = el; return el; },
    created: null,
    press(k, extra) {
      const ev = Object.assign({ key: k, target: { tagName: "BODY" }, prevented: false, preventDefault() { this.prevented = true; } }, extra);
      listeners.keydown(ev);
      return ev;
    }
  };
  return doc;
}

function booted(n, withBox) {
  const c = loadCore();
  const doc = makeDoc(n, withBox);
  c.SD.boot(doc, {});
  return { c, doc };
}

let { c, doc } = booted(5);
check("boot adds one keydown listener and a scroll listener", typeof doc.listeners.keydown === "function" && doc.win.listeners.scroll.length === 1);

let ev = doc.press("ArrowDown");
check("arrows are left alone while not presenting", !ev.prevented && doc.state.scrolledTo.length === 0);
ev = doc.press("Escape");
check("Esc is left alone while not presenting", !ev.prevented && doc.box.checked === false);

ev = doc.press("p");
check("P turns present mode on, handled", ev.prevented && doc.box.checked === true);
check("the counter shows 1 / 5", doc.count.textContent === "1 / 5");
doc.press("ArrowRight");
check("ArrowRight moves to the next slide: 2 / 5", doc.state.scrollY === 700 && doc.count.textContent === "2 / 5");
doc.press("PageDown");
check("Page Down moves on: 3 / 5", doc.count.textContent === "3 / 5");
doc.press("ArrowDown");
check("ArrowDown moves on: 4 / 5", doc.count.textContent === "4 / 5");
doc.press("ArrowLeft");
check("ArrowLeft goes back: 3 / 5", doc.count.textContent === "3 / 5");
doc.press("PageUp");
doc.press("ArrowUp");
check("Page Up and ArrowUp go back to 1 / 5", doc.count.textContent === "1 / 5");
doc.press("ArrowUp");
check("moving back from the first slide stays on it", doc.count.textContent === "1 / 5" && doc.state.scrollY === 0);
doc.press("End");
check("End jumps to the last slide: 5 / 5", doc.count.textContent === "5 / 5" && doc.state.scrollY === 2800);
doc.press("ArrowDown");
check("moving on from the last slide stays on it", doc.count.textContent === "5 / 5" && doc.state.scrollY === 2800);
doc.press("Home");
check("Home jumps to the first slide: 1 / 5", doc.count.textContent === "1 / 5" && doc.state.scrollY === 0);
doc.state.scrollY = 1400; doc.win.listeners.scroll[0]();
check("scrolling updates the counter: 3 / 5", doc.count.textContent === "3 / 5");
ev = doc.press("Escape");
check("Esc leaves present mode, handled", ev.prevented && doc.box.checked === false && doc.count.textContent === "");
ev = doc.press("P");
check("capital P toggles too", ev.prevented && doc.box.checked === true);
doc.press("p");
check("P again turns it off", doc.box.checked === false && doc.count.textContent === "");
check("unrelated keys are not handled", !doc.press("x").prevented && !doc.press("Enter").prevented);

// toggling keeps your place
({ c, doc } = booted(5));
doc.state.scrollY = 1400; // reading slide 3
doc.press("p");
check("P keeps the reading place: opens on the slide being read", doc.state.scrollY === 1400 && doc.count.textContent === "3 / 5");

// keys boot filters out never reach present
({ c, doc } = booted(3));
doc.press("p", { metaKey: true });
doc.press("p", { ctrlKey: true });
doc.press("p", { target: { tagName: "INPUT" } });
doc.press("p", { target: { tagName: "DIV", isContentEditable: true } });
check("P with Cmd or Ctrl held, or typed into an input, does nothing", doc.box.checked === false);

// print and reset restore the reading page
({ c, doc } = booted(4));
doc.press("p"); doc.press("ArrowDown");
check("present mode is on with a counter before print", doc.box.checked && doc.count.textContent === "2 / 4");
check("boot wires print to beforeprint", doc.win.listeners.beforeprint.length === 1);
doc.win.listeners.beforeprint[0]();
check("print leaves the reading page: switch off, counter cleared", doc.box.checked === false && doc.count.textContent === "");
doc.press("p");
check("present mode can be turned on again", doc.box.checked === true);
c.SD.reset(doc, {});
check("SD.reset restores the plain reading page", doc.box.checked === false && doc.count.textContent === "");

// a document with no slides: P is not handled
({ c, doc } = booted(0));
ev = doc.press("p");
check("with no slides, P is not handled", !ev.prevented && doc.box.checked === false);

// a page that took only the body, with no controls, gets a checkbox on first use
({ c, doc } = booted(3, false));
ev = doc.press("p");
check("with no #sd-present in the page, P creates one and turns it on",
  ev.prevented && doc.created && doc.created.attrs.type === "checkbox" && doc.created.attrs.id === "sd-present" &&
  doc.created.attrs.hidden === "" && doc.created.checked === true);

check("no hook errors", SD.errors.length === 0 && c.SD.errors.length === 0);

if (fail) { console.error("\npresent: " + fail + " FAILED"); process.exit(1); }
console.log("\npresent: PASS");

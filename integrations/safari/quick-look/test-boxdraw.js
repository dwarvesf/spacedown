// test-boxdraw.js: box-drawing code blocks (Resources/boxdraw.js). Owned by the
// box-diagram node; docs/contract-r1.md. Run: node test-boxdraw.js  ->  "boxdraw: PASS".
const { loadCore } = require("./load-core");

let fail = 0;
function check(name, cond) {
  if (cond) { console.log("  ok: " + name); } else { console.error("  FAIL: " + name); fail++; }
}
const count = (s, re) => (s.match(re) || []).length;

const SD = loadCore().SD;
const boxdraw = SD.plugin("boxdraw");
check("boxdraw registers with SD, first", !!boxdraw && SD.plugins()[0] === "boxdraw");

// Fenced block with box-drawing characters is marked.
let r = SD.render("```\n┌─┐\n│ │\n└─┘\n```");
check("box-drawing fence gets sd-boxdraw", /<pre class="sd-boxdraw"><code>┌─┐/.test(r.body));
check("css gives sd-boxdraw line-height 1.2", /pre\.sd-boxdraw[^{]*\{[^}]*line-height:\s*1\.2/.test(r.css));

// Arrow glyphs mark too, and a highlighted block keeps its code classes.
r = SD.render("```js\nvar a = 1; // a → b\n```");
check("arrow glyph in a highlighted fence is marked", /<pre class="sd-boxdraw"><code class="hljs language-js">/.test(r.body));
r = SD.render("```\nA ▶ B\n```");
check("triangle arrow is marked", count(r.body, /sd-boxdraw/g) === 1);

// Negative cases: plain code, inline code, and prose stay untouched.
r = SD.render("```\nplain text\nline two\n```");
check("plain code block is not marked", !/sd-boxdraw/.test(r.body) && /<pre><code>plain text/.test(r.body));
r = SD.render("```js\nvar a = 1;\n```");
check("plain highlighted block is not marked", !/sd-boxdraw/.test(r.body));
r = SD.render("Use `└` inline, and a ┌ in prose.");
check("inline code and prose are not marked", !/sd-boxdraw/.test(r.body));

// Mixed document: only the drawn block is marked.
r = SD.render("```\nplain\n```\n\n```\n├── a\n└── b\n```\n\n```\nplain two\n```");
check("only the tree block of three is marked", count(r.body, /<pre/g) === 3 && count(r.body, /sd-boxdraw/g) === 1);

// Indented code block works the same.
r = SD.render("    ┌─┐\n    └─┘\n");
check("indented code block is marked", /<pre class="sd-boxdraw">/.test(r.body));

check("no hook errors", SD.errors.length === 0);

if (fail) { console.error("\nboxdraw: " + fail + " FAILED"); process.exit(1); }
console.log("\nboxdraw: PASS");

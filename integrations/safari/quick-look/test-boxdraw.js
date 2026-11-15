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

// The built Quick Look skin carries the diagram fallback face and lists it after iA Mono in
// the mono stack. iA Writer Mono has no box-drawing glyphs; without this face they fall back
// per glyph to a font with another advance and the diagram edges drift.
const { execFileSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
function skinHasDiagramFallback(css) {
  const face = css.match(/@font-face\s*\{[^}]*font-family:\s*"SD Diagram Fallback"[^}]*\}/);
  if (!face) return false;
  if (!/src:\s*local\("Menlo"\)/.test(face[0])) return false;
  if (!/unicode-range:[^;]*U\+2500-25FF/.test(face[0])) return false;
  const stack = css.match(/--ql-mono-font:\s*([^;]+);/);
  if (!stack) return false;
  const fams = stack[1].split(",").map((f) => f.trim().replace(/"/g, ""));
  const fb = fams.indexOf("SD Diagram Fallback");
  return fb > fams.lastIndexOf("iA Writer Mono S") && fams.lastIndexOf("iA Writer Mono S") > -1;
}
const skinOut = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "ql-skin-")), "skin.css");
execFileSync(path.join(__dirname, "..", "..", "..", "scripts", "build-ql-skin"), [skinOut]);
const skinCss = fs.readFileSync(skinOut, "utf8");
check("built skin carries the SD Diagram Fallback face, Menlo, box-drawing range, after iA Mono",
  skinHasDiagramFallback(skinCss));
check("negative control: skin without the face fails the check",
  !skinHasDiagramFallback(skinCss.replace(/@font-face\s*\{[^}]*SD Diagram Fallback[^}]*\}/, "")));
check("negative control: face listed before iA Mono fails the check",
  !skinHasDiagramFallback(skinCss.replace(/(--ql-mono-font:\s*)"iA Writer Mono V", "iA Writer Mono S", "SD Diagram Fallback"/, '$1"SD Diagram Fallback", "iA Writer Mono V", "iA Writer Mono S"')));

check("no hook errors", SD.errors.length === 0);

if (fail) { console.error("\nboxdraw: " + fail + " FAILED"); process.exit(1); }
console.log("\nboxdraw: PASS");

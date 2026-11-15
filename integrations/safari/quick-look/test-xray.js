// test-xray.js: the Writing X-ray lens (Resources/xray.js). Owned by the X-ray node;
// docs/contract-r1.md. Run: node test-xray.js  ->  exit 0 + "xray: PASS".
const { loadCore } = require("./load-core");

let fail = 0;
function check(name, cond) {
  if (cond) { console.log("  ok: " + name); } else { console.error("  FAIL: " + name); fail++; }
}

const ctx = loadCore();
const SD = ctx.SD;
const xray = SD.plugin("xray");
check("xray registers with SD", !!xray && SD.plugins().includes("xray"));

// The core must call the lens on every render, with the validated settings.
const seen = [];
const transform = xray.transform;
xray.transform = (html, cfg) => { seen.push(cfg); return transform(html, cfg); };
const out = SD.render("# T\n\nOne sentence.", { xraySentenceWords: 12 });
check("render calls the xray transform with its settings",
  seen.length === 1 && seen[0].xraySentenceWords === 12 && /<h1/.test(out.body));
check("no hook errors", SD.errors.length === 0);

if (fail) { console.error("\nxray: " + fail + " FAILED"); process.exit(1); }
console.log("\nxray: PASS");

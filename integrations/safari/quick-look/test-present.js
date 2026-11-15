// test-present.js: Present mode (Resources/present.js). Owned by the Present node;
// docs/contract-r1.md. Run: node test-present.js  ->  exit 0 + "present: PASS".
const { loadCore } = require("./load-core");

let fail = 0;
function check(name, cond) {
  if (cond) { console.log("  ok: " + name); } else { console.error("  FAIL: " + name); fail++; }
}

const ctx = loadCore();
const SD = ctx.SD;
const present = SD.plugin("present");
check("present registers with SD, after xray",
  !!present && SD.plugins().indexOf("present") > SD.plugins().indexOf("xray"));

// Render time: the core calls the transform.
let rendered = 0;
const transform = present.transform;
present.transform = (html, cfg) => { rendered++; return transform(html, cfg); };
SD.render("## One\n\n---\n\n## Two");
check("render calls the present transform", rendered === 1);

// Page time: SD.boot routes keys to the present key hook.
const keys = [];
const key = present.key;
present.key = (ev, cfg) => { keys.push(ev.key); return key(ev, cfg); };
const listeners = {};
SD.boot({ addEventListener: (t, f) => { listeners[t] = f; }, defaultView: null });
listeners.keydown({ key: "p", target: { tagName: "BODY" }, preventDefault() {} });
check("boot routes the P key to present", keys.includes("p"));
check("no hook errors", SD.errors.length === 0);

if (fail) { console.error("\npresent: " + fail + " FAILED"); process.exit(1); }
console.log("\npresent: PASS");

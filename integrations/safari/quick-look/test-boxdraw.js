// test-boxdraw.js: box-drawing code blocks (Resources/boxdraw.js). Owned by the
// box-diagram node; docs/contract-r1.md. Run: node test-boxdraw.js  ->  "boxdraw: PASS".
const { loadCore } = require("./load-core");

let fail = 0;
function check(name, cond) {
  if (cond) { console.log("  ok: " + name); } else { console.error("  FAIL: " + name); fail++; }
}

const SD = loadCore().SD;
const boxdraw = SD.plugin("boxdraw");
check("boxdraw registers with SD, first", !!boxdraw && SD.plugins()[0] === "boxdraw");

let calls = 0;
const transform = boxdraw.transform;
boxdraw.transform = (html, cfg) => { calls++; return transform(html, cfg); };
SD.render("```\n┌─┐\n└─┘\n```");
check("render calls the boxdraw transform", calls === 1);
check("no hook errors", SD.errors.length === 0);

if (fail) { console.error("\nboxdraw: " + fail + " FAILED"); process.exit(1); }
console.log("\nboxdraw: PASS");

// test-contract.js: the release-1 contract (docs/contract-r1.md) holds. The SD plug-in
// registry calls each hook, settings validate and default, and every copy of the
// contract that lives outside ql-render.js (Swift defaults, Swift load order, App Group
// id in entitlements and scripts/sd-settings) still matches it.
// Run: node test-contract.js  ->  exit 0 + "contract: PASS".
const fs = require("fs");
const path = require("path");
const { CORE_FILES, loadCore } = require("./load-core");

const safari = path.join(__dirname, "..");
const root = path.join(safari, "..", "..");
let fail = 0;
function check(name, cond) {
  if (cond) { console.log("  ok: " + name); } else { console.error("  FAIL: " + name); fail++; }
}

const ctx = loadCore();
const SD = ctx.SD;
check("SD exposes the contract API",
  SD && SD.contract === 1 && ["config", "register", "plugins", "plugin", "render", "boot", "reset"]
    .every((k) => typeof SD[k] === "function"));
check("mdToHtml still exposed", typeof ctx.mdToHtml === "function");

// Settings.
const d = SD.config();
check("config() is the defaults", JSON.stringify(Object.assign({}, d, { surface: undefined })) ===
  JSON.stringify(Object.assign({}, SD.DEFAULTS, { surface: undefined })) && d.surface === "quicklook");
const c = SD.config({ theme: "paper", appearance: "neon", textSize: 99, xrayEnabled: 1,
  xrayDashes: "yes", xraySentenceWords: 7.6, xrayFillerWords: ["  very ", 3, ""], bogus: 1, surface: "cli" });
check("valid enum kept, invalid enum dropped", c.theme === "paper" && c.appearance === "system");
check("ints clamped to range", c.textSize === 32 && c.xraySentenceWords === 8);
check("bool from 1, wrong type dropped", c.xrayEnabled === true && c.xrayDashes === true);
check("string list cleaned", JSON.stringify(c.xrayFillerWords) === '["very"]');
check("unknown key dropped, surface kept", !("bogus" in c) && c.surface === "cli");
check("defaults not mutated by a config", SD.DEFAULTS.xrayFillerWords.length > 1);

// Registry: a probe plugin sees every render-time hook.
const seen = [];
SD.register({
  id: "probe", order: 50,
  transform: (html, cfg) => { seen.push("transform:" + cfg.textSize); return html + "<!--probe-->"; },
  css: () => ".probe{}",
  controls: () => '<input type="checkbox" id="probe" hidden>',
  toolbar: () => '<label for="probe">P</label>'
});
SD.register({ id: "boom", order: 60, transform: () => { throw new Error("bang"); }, css: () => { throw new Error("css"); } });
const page = SD.render("# Hi\n\nText.", { textSize: 20 });
check("transform gets the validated config", seen.includes("transform:20"));
check("transform output lands in the body", page.body.includes("<!--probe-->") && /<h1/.test(page.body));
check("a throwing hook is skipped and logged", SD.errors.some((e) => e.startsWith("boom.transform")) &&
  SD.errors.some((e) => e.startsWith("boom.css")));
check("css collected with the toolbar CSS", page.css.includes(".probe{}") && page.css.includes(".sd-ql-toolbar"));
check("controls come before the toolbar", page.chrome.indexOf('id="probe"') >= 0 &&
  page.chrome.indexOf('id="probe"') < page.chrome.indexOf("sd-ql-toolbar"));
check("toolbar items inside the shared bar", /<div class="sd-ql-toolbar"[^>]*><label for="probe">/.test(page.chrome));
check("html attrs carry the settings", page.attrs.includes('data-sd-theme="ia"') && page.attrs.includes("--ql-size:20px"));
SD.register({ id: "probe", order: 50 });
check("re-register by id replaces", SD.plugins().filter((id) => id === "probe").length === 1 &&
  !SD.render("x").body.includes("<!--probe-->"));
check("no toolbar items -> no chrome, no toolbar CSS", (() => {
  const bare = loadCore();
  ["boxdraw", "xray", "present"].forEach((id) => bare.SD.register({ id }));
  const p = bare.SD.render("x");
  return p.chrome === "" && !p.css.includes("sd-ql-toolbar");
})());
check("order: lower runs first", SD.plugins().indexOf("probe") < SD.plugins().indexOf("boom"));

// Page time, with a minimal fake document.
function fakeDoc() {
  const listeners = {}, winListeners = {};
  return {
    listeners, winListeners,
    addEventListener: (t, f) => { listeners[t] = f; },
    defaultView: { addEventListener: (t, f) => { winListeners[t] = f; } }
  };
}
const calls = [];
SD.register({
  id: "pager", order: 70,
  init: (doc, cfg) => calls.push("init:" + cfg.surface),
  key: (ev) => { calls.push("key:" + ev.key); return ev.key === "p"; },
  print: () => calls.push("print"),
  reset: () => calls.push("reset")
});
const doc = fakeDoc();
SD.boot(doc, { surface: "cli" });
let prevented = 0;
const ev = (key, extra) => Object.assign({ key, target: { tagName: "BODY" }, preventDefault: () => prevented++ }, extra);
doc.listeners.keydown(ev("p"));
doc.listeners.keydown(ev("q"));
doc.listeners.keydown(ev("p", { metaKey: true }));
doc.listeners.keydown(ev("p", { target: { tagName: "INPUT" } }));
doc.winListeners.beforeprint();
SD.reset(doc);
check("boot calls init with the config", calls.includes("init:cli"));
check("key routed; true -> preventDefault once", calls.filter((x) => x === "key:p").length === 1 &&
  calls.includes("key:q") && prevented === 1);
check("modified keys and typing are not routed", calls.filter((x) => x.startsWith("key:")).length === 2);
check("beforeprint -> print, SD.reset -> reset", calls.includes("print") && calls.includes("reset"));

// Mirrors of the contract outside ql-render.js.
const swiftSettings = fs.readFileSync(path.join(safari, "shared", "SpacedownSettings.swift"), "utf8");
const block = /static let defaults: \[String: Any\] = \[([\s\S]*?)\n    \]/.exec(swiftSettings);
const swiftDefaults = {};
if (block) {
  for (const m of block[1].matchAll(/^\s*"(\w+)": (.+?),?$/gm)) swiftDefaults[m[1]] = JSON.parse(m[2]);
}
check("Swift defaults == SD.DEFAULTS", JSON.stringify(swiftDefaults, Object.keys(SD.DEFAULTS).sort()) ===
  JSON.stringify(SD.DEFAULTS, Object.keys(SD.DEFAULTS).sort()) &&
  Object.keys(swiftDefaults).length === Object.keys(SD.DEFAULTS).length);

const provider = fs.readFileSync(path.join(__dirname, "Sources", "MarkdownPreviewProvider.swift"), "utf8");
check("Swift loads scripts from load-order.txt only",
  provider.includes('forResource: "load-order", withExtension: "txt"') &&
  (provider.match(/loadScript\(ctx, bundle, "/g) || []).length === 0);
check("load-order.txt: vendor, ql-render, then plug-ins; every file exists",
  CORE_FILES.indexOf("highlight.min.js") < CORE_FILES.indexOf("ql-render.js") &&
  CORE_FILES.indexOf("ql-render.js") === CORE_FILES.length - 4 &&
  CORE_FILES.every((f) => fs.existsSync(path.join(__dirname, "Resources", f))));
check("plug-ins load in registry order", JSON.stringify(SD.plugins().filter((id) => ["boxdraw", "xray", "present"].includes(id))) ===
  JSON.stringify(["boxdraw", "xray", "present"]));

const group = (/static let suiteName = "([^"]+)"/.exec(swiftSettings) || [])[1];
const groupFiles = [
  path.join(safari, "entitlements", "app.entitlements"),
  path.join(safari, "entitlements", "app.release.entitlements"),
  path.join(__dirname, "SpacedownQL.entitlements"),
  path.join(root, "scripts", "sd-settings")
];
check("one App Group id in app, extension and sd-settings", !!group && groupFiles.every((f) => {
  const t = fs.readFileSync(f, "utf8");
  return t.includes(group) && (!f.endsWith(".entitlements") || t.includes("com.apple.security.application-groups"));
}));

if (fail) { console.error("\ncontract: " + fail + " FAILED"); process.exit(1); }
console.log("\ncontract: PASS");

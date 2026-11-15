// load-core.js: load the Quick Look render core into a fresh node vm context, in the
// order Resources/load-order.txt names. The appex (MarkdownRenderer) and the CLI read
// the same file, so every host loads the same scripts in the same order.
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const RESOURCES = path.join(__dirname, "Resources");
const CORE_FILES = fs.readFileSync(path.join(RESOURCES, "load-order.txt"), "utf8")
  .split("\n").map((l) => l.trim()).filter((l) => l && !l.startsWith("#"));

function loadCore(dir = RESOURCES) {
  const ctx = {};
  // Make the UMD bundles take their global-assignment branch (no module/exports here).
  ctx.self = ctx; ctx.window = ctx; ctx.global = ctx; ctx.globalThis = ctx;
  vm.createContext(ctx);
  for (const f of CORE_FILES) {
    vm.runInContext(fs.readFileSync(path.join(dir, f), "utf8"), ctx, { filename: f });
  }
  return ctx;
}

module.exports = { CORE_FILES, loadCore };

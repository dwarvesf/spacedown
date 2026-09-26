#!/usr/bin/env node
// render-file.js: run a markdown file through the EXACT Quick Look render pipeline
// (marked + katex + ql-render.js in a clean vm context) without touching the GUI.
// The headless twin of spacebar-in-Finder: use it to debug a doc that previews
// wrong, or to diff repo sources against the installed appex.
//
//   node render-file.js <file.md>                 # summary line (repo Resources)
//   node render-file.js <file.md> --out out.html  # also write the full HTML
//   node render-file.js <file.md> --app           # use the INSTALLED appex's
//                                                 # resources instead of the repo's
//
// The summary counts the shapes this pipeline has historically broken on:
// frontmatter table, callouts, leaked [!markers], katex spans, task-list items,
// <br> hard breaks, and unresolved MDP placeholders (always a bug when nonzero).
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const args = process.argv.slice(2);
const file = args.find((a) => !a.startsWith("--"));
if (!file) {
  console.error("usage: node render-file.js <file.md> [--out out.html] [--app]");
  process.exit(64);
}
const outIdx = args.indexOf("--out");
const outPath = outIdx >= 0 ? args[outIdx + 1] : null;
const dir = args.includes("--app")
  ? path.join(process.env.HOME, "Applications/Spacedown.app/Contents/PlugIns/SpacedownQL.appex/Contents/Resources")
  : path.join(__dirname, "Resources");

const ctx = {};
ctx.self = ctx; ctx.window = ctx; ctx.global = ctx; ctx.globalThis = ctx;
vm.createContext(ctx);
for (const f of ["marked.min.js", "katex.min.js", "highlight.min.js", "ql-render.js"])
  vm.runInContext(fs.readFileSync(path.join(dir, f), "utf8"), ctx, { filename: f });

const t0 = Date.now();
const html = ctx.mdToHtml(fs.readFileSync(file, "utf8"));
const count = (re) => (html.match(re) || []).length;
const placeholders = count(/MDP(CALLOUT|MATHPLACEHOLDER)\d+ENDMDP/g);
console.log(
  `${path.basename(file)}: ${html.length}b in ${Date.now() - t0}ms |`,
  `fm-table:${count(/class="mdp-frontmatter"/g)}`,
  `callouts:${count(/<blockquote class="mdp-callout/g)}`,
  `literal-[!:${count(/\[!/g)}`,
  `katex:${count(/class="katex/g)}`,
  `tasklist:${count(/task-list-item/g) - 1}`,
  `br:${count(/<br\s*\/?>/g)}`,
  `leaked-placeholders:${placeholders}${placeholders ? "  <-- BUG" : ""}`
);
if (outPath) {
  fs.writeFileSync(outPath, html);
  console.log("wrote", outPath);
}
process.exit(placeholders ? 1 : 0);

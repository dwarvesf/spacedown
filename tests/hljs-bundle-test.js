// hljs-bundle-test.js: the custom highlight.js build still knows every language and alias
// the Quick Look preview promises, and stays small. Rebuild with scripts/hljs-build.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const file = path.join(__dirname, "..", "integrations/safari/quick-look/Resources/highlight.min.js");
const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(file, "utf8") + "\nthis.hljs = hljs;", sandbox);
const hljs = sandbox.hljs;

let failed = 0;
function check(name, ok) { console.log((ok ? "  ok   " : "  FAIL ") + name); if (!ok) failed++; }

const samples = {
  bash: "echo \"hi\" | grep -v x # c", sh: "for f in *; do echo $f; done", shell: "$ ls -la", zsh: "echo $HOME",
  javascript: "const a = () => 1;", js: "function f() { return 'x'; }",
  typescript: "interface A { b: number }", ts: "let x: string = 'a';",
  json: "{\"a\": [1, true, null]}", yaml: "a: 1\nb: [x]", yml: "a: true",
  ini: "[s]\nk = v", toml: "[tool]\nname = \"x\"",
  python: "def f(x):\n  return 'a'", py: "print('x')",
  go: "func main() { x := 1 }", rust: "fn main() { let x = 1; }", rs: "fn f() {}",
  swift: "let x: Int = 1", sql: "SELECT a FROM b WHERE c = 1;",
  xml: "<a b=\"c\">d</a>", html: "<div class=\"x\">y</div>",
  css: "a { color: red; }", markdown: "# Title\n*x*", md: "- item",
  diff: "--- a\n+++ b\n@@ -1 +1 @@\n-x\n+y", dockerfile: "FROM node:20\nRUN npm ci",
  makefile: "all:\n\tgo build", make: "x: y\n\techo",
  plaintext: "plain text",
};
for (const [lang, code] of Object.entries(samples)) {
  if (!hljs.getLanguage(lang)) { check(lang + " is registered", false); continue; }
  const out = hljs.highlight(code, { language: lang }).value;
  const bare = lang === "plaintext";
  check(lang + (bare ? " renders" : " gets token spans"), bare ? out.includes("plain") : /class="hljs-/.test(out));
}
check("an unlisted language stays unknown", !hljs.getLanguage("zebra") && !hljs.getLanguage("haskell"));
const bytes = fs.statSync(file).size;
check("bundle is under 100000 bytes (" + bytes + ")", bytes < 100000);
console.log(failed ? "hljs-bundle-test: " + failed + " failed" : "hljs-bundle-test: all passed");
process.exit(failed ? 1 : 0);

// Wrap render-file.js body output the way MarkdownPreviewProvider.buildPreviewHTML does:
// panel reset, then katex css, md-style.html, hljs theme, ql-reading css.
const fs = require("fs");
const path = require("path");
const [bodyFile, resDir, outFile] = process.argv.slice(2);
const r = (n) => fs.readFileSync(path.join(resDir, n), "utf8");
let body = fs.readFileSync(bodyFile, "utf8");
const m = body.match(/<body[^>]*>([\s\S]*)<\/body>/i);
if (m) body = m[1];
const head =
  `<style>${r("katex.min.css")}</style>\n` +
  r("md-style.html") + "\n" +
  `<style>${r("hljs-theme.css")}</style>\n` +
  `<style>${r("ql-reading.css")}</style>\n`;
const page = `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>body { margin: 0; padding: 16px 22px; }</style>
${head}
</head><body>${body}</body></html>`;
fs.writeFileSync(outFile, page);
console.log("wrote " + outFile + " (" + page.length + " bytes)");

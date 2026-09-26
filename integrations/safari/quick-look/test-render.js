// test-render.js: deterministic proof of the Quick Look render core (no Xcode, no GUI).
// Loads the same vendored marked + katex + ql-render.js the appex uses, into a fresh
// JS context, and asserts a markdown fixture renders to HTML (heading + KaTeX markup),
// not literal markdown. Run: node test-render.js  ->  exit 0 + "ql-render: PASS".
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const dir = path.join(__dirname, "Resources");
const ctx = {};
// Make the UMD bundles take their global-assignment branch (no module/exports here).
ctx.self = ctx; ctx.window = ctx; ctx.global = ctx; ctx.globalThis = ctx;
vm.createContext(ctx);
for (const f of ["marked.min.js", "katex.min.js", "highlight.min.js", "ql-render.js"]) {
  vm.runInContext(fs.readFileSync(path.join(dir, f), "utf8"), ctx, { filename: f });
}

let fail = 0;
function check(name, cond) {
  if (cond) { console.log("  ok: " + name); } else { console.error("  FAIL: " + name); fail++; }
}

check("marked loaded", typeof ctx.marked !== "undefined" && typeof ctx.marked.parse === "function");
check("katex loaded", typeof ctx.katex !== "undefined" && typeof ctx.katex.renderToString === "function");
check("mdToHtml exposed", typeof ctx.mdToHtml === "function");

const out = ctx.mdToHtml("# Heading One\n\nText with $E=mc^2$ inline.\n\n$$\\sum_{i=1}^{n} i$$\n");
check("rendered <h1> heading (not raw #)", /<h1[ >]/.test(out) && !/# Heading One/.test(out));
check("inline math -> katex markup (not raw $)", /class="katex/.test(out) && !/\$E=mc\^2\$/.test(out));
check("display math -> katex display", /katex-display|displaystyle|\\sum|class="katex/.test(out));
check("code fence still works", /<pre|<code/.test(ctx.mdToHtml("```\nx=1\n```\n")));
check("no-math doc unaffected", ctx.mdToHtml("# Plain\n\njust text").includes("<h1"));

// Wikilinks: [[target]] and [[target|title]] render as text (the panel has nowhere to
// navigate), while a code span keeps its literal brackets.
const wl = ctx.mdToHtml("See [[station-notes]] and [[calibration-log|the log]], not `[[raw]]`.");
check("[[target]] -> wikilink span", wl.includes('<span class="wikilink">station-notes</span>'));
check("[[target|title]] -> title text", wl.includes('<span class="wikilink">the log</span>') && !wl.includes("calibration-log"));
check("wikilink inside a code span stays literal", wl.includes("<code>[[raw]]</code>"));
check("wikilink text is escaped", ctx.mdToHtml("[[a<b>]]").includes("a&lt;b&gt;"));

// Frontmatter: leading --- block renders as the sd-frontmatter table (same contract
// as assets/frontmatter-to-table.py), odd shapes fall back to a yaml fence, and a
// mid-document --- stays a plain thematic break.
const fmDoc = "---\ntitle: Spring Rainfall Review (Draft)\nstatus: active\ntags: [a, b]\nmeta:\n  depth: 2\n---\n\n# Body\n";
const fmOut = ctx.mdToHtml(fmDoc);
check("frontmatter -> sd-frontmatter table", fmOut.includes('class="sd-frontmatter"') && fmOut.includes("Spring Rainfall Review"));
check("frontmatter not mashed into a heading", !/<h\d[^>]*>[^<]*title:/.test(fmOut));
check("inline list + nested key flatten", fmOut.includes("a, b") && fmOut.includes("meta.depth"));
check("body after frontmatter still renders", /<h1[ >]/.test(fmOut));
check("odd frontmatter falls back to yaml fence", /<pre|<code/.test(ctx.mdToHtml("---\njust some stray text\n---\nbody\n")));
check("no frontmatter -> untouched", !ctx.mdToHtml("# Plain\n\n---\n\ntext").includes("sd-frontmatter"));

// Callouts: "> [!type] title" becomes a classed blockquote with a styled head line;
// unknown types fall back to note styling; a plain blockquote is untouched.
const co = ctx.mdToHtml("> [!important] Board narrowed\n> The candidate set is now smaller.\n");
check("callout -> classed blockquote", co.includes('class="sd-callout sd-callout-important"'));
check("callout head carries label + title", /sd-callout-head[^>]*>Important<span[^>]*> · Board narrowed/.test(co));
check("callout body survives", co.includes("candidate set"));
check("unknown callout type -> note styling", ctx.mdToHtml("> [!zebra] Hm\n> body\n").includes("sd-callout-note"));
check("plain blockquote untouched", !ctx.mdToHtml("> just a quote\n").includes('<blockquote class="sd-callout'));

// Short table columns get sd-tight so auto layout cannot collapse them to their
// longest word; the prose column that competes for the width stays wrappable.
const tt = ctx.mdToHtml("| Date | Event |\n|---|---|\n| 1960s to 1970s | Phototypesetting replaced hot metal across the trade, and the craft went with it |\n");
check("short column marked tight", /<t[hd] class="sd-tight">\s*Date/.test(tt) && tt.includes('<td class="sd-tight">1960s to 1970s'));
check("prose column left wrappable", /<td>Phototypesetting/.test(tt));
const wide = ctx.mdToHtml("| A | B |\n|---|---|\n| short | tiny |\n");
check("all-short table untouched", !wide.includes("sd-tight"));
const long2 = ctx.mdToHtml("| Statement of the position taken | Consequence |\n|---|---|\n| " + "x".repeat(40) + " | " + "y".repeat(40) + " |\n");
check("no short column, nothing marked", !long2.includes("sd-tight") && !long2.includes("sd-narrow"));
const label = ctx.mdToHtml("| Element | Coastal weather station |\n|---|---|\n| What keeps the gauge accurate | " + "Nothing at all changes it, and the weekly calibration log shows why. ".repeat(2) + " |\n");
check("label column marked narrow", label.includes('<td class="sd-narrow">What keeps the gauge'));
check("one prose column stays in the reading column", !label.includes("sd-wide"));
const two = "| Pattern | What the week looks like | What it produces |\n|---|---|---|\n| The frontal pattern | " +
  "The week brings long, steady rain from the west. ".repeat(2) + " | " + "The gauges fill slowly and evenly across every station. ".repeat(6) + " |\n";
const twoOut = ctx.mdToHtml(two);
check("two prose columns make the table wide", twoOut.includes('<table class="sd-wide">'));
// Floors follow content: the column holding three times the prose gets the wider floor.
const floors = (twoOut.match(/min-width:(\d+)ch/g) || []).map((s) => +s.match(/\d+/)[0]);
check("every column of a wide table carries a floor", floors.length >= 6);
check("floors ordered by content size", Math.max(...floors) > Math.min(...floors));
check("floors stay inside the readable band", floors.every((f) => f >= 22 && f <= 52));
check("label column is not nowrapped", !label.includes('<td class="sd-tight">What keeps the gauge'));

// Currency dollars must not be parsed as inline math (pandoc rule: closing $ not
// followed by a digit; no | inside a candidate), while real inline math still renders.
const cur = ctx.mdToHtml("| a | b |\n|---|---|\n| $5K | **EUR 200K** setup $930K |\n");
check("currency in table stays prose", cur.includes("$5K") && cur.includes("$930K") && !cur.includes("katex"));
check("real inline math still renders", ctx.mdToHtml("value $E=mc^2$ here").includes('class="katex'));

// Task-list items get the class that hides the double bullet+checkbox marker.
const task = ctx.mdToHtml("- [ ] read page\n- [x] book consult\n");
check("task-list items classed", (task.match(/task-list-item/g) || []).length >= 2);
check("extra CSS block emitted", task.includes("li.task-list-item{list-style:none}"));

// Hard line breaks (Obsidian default): a single newline inside a paragraph or a
// multi-line blockquote becomes <br> instead of joining into one wall of text.
check("single newline -> <br>", /<br\s*\/?>/.test(ctx.mdToHtml("line one\nline two\n")));
check("multi-line callout keeps line structure", /<br\s*\/?>/.test(ctx.mdToHtml("> [!note] History\n> **Wave 1**: a\n> **Wave 2**: b\n")));

// Syntax highlighting. Without these, deleting the whole highlight pass still printed
// PASS and still installed, since build-safari.sh gates the install on this file.
const hl = ctx.mdToHtml("```py\nprint('x')\n```\n");
check("known language gets hljs token spans", /class="hljs language-py"/.test(hl) && /class="hljs-/.test(hl));
// Quotes stay escaped, and the entity form changes across the round trip: marked writes
// &#39;, the unescape pass restores the glyph, hljs re-escapes it as &#x27;. Both render
// the same, so assert the token span and accept either spelling.
check("highlighted code keeps its text",
      hl.includes("print") && /hljs-string[^>]*>(&#39;|&#x27;)x(&#39;|&#x27;)/.test(hl));
const unknown = ctx.mdToHtml("```zebra\nx = 1\n```\n");
check("unknown language left untouched", unknown.includes('class="language-zebra"') && !/class="hljs/.test(unknown));

// Negative control, the real one: a context built WITHOUT highlight.min.js must render
// the same fence unhighlighted rather than throwing or losing the code.
const bare = {};
bare.self = bare; bare.window = bare; bare.global = bare; bare.globalThis = bare;
vm.createContext(bare);
for (const f of ["marked.min.js", "katex.min.js", "ql-render.js"]) {
  vm.runInContext(fs.readFileSync(path.join(dir, f), "utf8"), bare, { filename: f });
}
const noHl = bare.mdToHtml("```py\nprint('x')\n```\n");
check("no highlighter -> plain fence, code intact", !/class="hljs/.test(noHl) && noHl.includes("print"));

// Wiring guards: a QLPreviewProvider extension is silently never called (infinite
// Finder spinner) unless Info.plist declares QLIsDataBasedPreview and the provider
// class conforms to QLPreviewingController.
const plist = fs.readFileSync(path.join(__dirname, "Info.plist"), "utf8");
check("Info.plist declares QLIsDataBasedPreview", /<key>QLIsDataBasedPreview<\/key>\s*<true\/>/.test(plist));
const provider = fs.readFileSync(path.join(__dirname, "Sources", "MarkdownPreviewProvider.swift"), "utf8");
check("provider conforms to QLPreviewingController", /QLPreviewProvider,\s*QLPreviewingController/.test(provider));

// The reading-skin harness (preview-skin.sh) hand-mirrors headCSS() in bash. It has already drifted twice:
// once missing the body reset (a shipped layout regression), once missing hljs-theme.css.
// Assert both lists name the same stylesheets, so adding one to headCSS() fails here.
const headSheets = (provider.match(/forResource: "([\w.-]+)", withExtension: "(css|html)"/g) || [])
  .map((s) => s.match(/"([\w.-]+)"/)[1]);
const harness = fs.readFileSync(
  path.join(__dirname, "preview-skin.sh"), "utf8");
const missing = headSheets.filter((name) => !harness.includes(name + "."));
check("reading-skin harness loads every stylesheet headCSS() loads",
      headSheets.length >= 4 && missing.length === 0);

// One Mach service name across the plist, the helper, the extension client and the
// mach-lookup exception. Renaming the plist alone once left the helper listening on a
// name launchd had not reserved and the extension looking up a name nobody served, so
// the Safari drop path returned "render helper unreachable" with nothing else failing.
const integrations = path.join(__dirname, "..");
const nameSources = {
  "helper plist": ["helper", "dfoundation.spacedown.render.plist"],
  "helper source": ["helper", "spacedown-render.swift"],
  "extension client": ["SpacedownDrop", "SpacedownDrop Extension", "SafariWebExtensionHandler.swift"],
  "mach-lookup entitlement": ["entitlements", "extension.entitlements"],
};
const serviceNames = new Set();
for (const [label, parts] of Object.entries(nameSources)) {
  const text = fs.readFileSync(path.join(integrations, ...parts), "utf8");
  const hits = text.match(/\bdfoundation\.spacedown[.\w-]*render\b/g) || [];
  // The idle-queue label is derived from the service name, so keep the base only.
  hits.forEach((h) => serviceNames.add(h.replace(/\.idle$/, "")));
  check(label + " names a render service", hits.length > 0);
}
check("one Mach service name across plist, helper, client, entitlement",
      serviceNames.size === 1);

if (fail) { console.error("\nql-render: " + fail + " FAILED"); process.exit(1); }
console.log("\nql-render: PASS");

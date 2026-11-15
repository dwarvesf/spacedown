// ql-render.js: turn markdown source into self-contained HTML, in-process, using
// marked (MD -> HTML) + KaTeX (math -> HTML). No DOM, no network: katex.renderToString
// is DOM-free, so this runs the same in a JSContext (the Quick Look appex) and in node
// (the test harness). Loaded AFTER vendor/marked.min.js + vendor/katex.min.js, which set
// `marked` and `katex` on the shared global.
//
// Math handling: extract $$...$$ (display) and $...$ (inline) BEFORE marked so it does
// not mangle the TeX, render each with katex.renderToString, swap back after parse via a
// plain alphanumeric placeholder marked leaves untouched. Known limitation: a literal $
// inside a code span/block is still treated as math (the appex preview is best-effort;
// the pandoc/browser path is the source of truth for tricky docs).
(function (global) {
  "use strict";

  // Frontmatter: JS port of assets/frontmatter-to-table.py (the pandoc/browser path).
  // Same tolerant contract: split each line on the FIRST ": ", never a real YAML parser;
  // anything odd (deep nesting, mixed shapes, stray text) falls back to a ```yaml fence.
  // The .sd-frontmatter CSS ships in md-style.html already. Omitted vs the python:
  // the (1)(2)(3) enum soft-break and the long-value clamp (its Show-more toggle lives
  // in the browser foot JS the appex does not load).
  var FM_SCALAR_RE = /^(true|false|null|-?\d+(\.\d+)?)$/i;

  function fmEsc(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  function fmValue(v) {
    v = v.trim();
    if (v === "") return "&nbsp;";
    if (v.charAt(0) === "[" && v.charAt(v.length - 1) === "]") {
      var inner = v.slice(1, -1).trim();
      v = inner
        ? inner.split(",").map(function (x) {
            return x.trim().replace(/^["']|["']$/g, "");
          }).join(", ")
        : "";
      if (v === "") return "&nbsp;";
    }
    if (FM_SCALAR_RE.test(v)) return '<span class="sd-fm-scalar">' + fmEsc(v) + "</span>";
    return fmEsc(v).replace(/`([^`]+)`/g, function (whole, code) {
      return "<code>" + code + "</code>";
    });
  }

  function fmSplitKV(line) {
    var m = /^([^:]+):(.*)$/.exec(line);
    if (!m) return null;
    var after = m[2];
    return [m[1].trim(), after.charAt(0) === " " ? after.slice(1) : after];
  }

  // rows for one level of indented children or a block list under `parent`;
  // returns { rows, next, ok } with ok=false signalling the fence fallback.
  function fmChildren(block, start, parent) {
    var listItems = [], childRows = [], sawIndent = false, i = start;
    while (i < block.length) {
      var line = block[i];
      if (line.trim() === "") { i++; continue; }
      if (!/^\s/.test(line)) break;
      sawIndent = true;
      var stripped = line.trim();
      if (stripped.indexOf("- ") === 0) {
        listItems.push(stripped.slice(2).trim().replace(/^["']|["']$/g, ""));
        i++;
        continue;
      }
      var kv = fmSplitKV(stripped);
      if (!kv || kv[1].trim() === "") return { rows: [], next: start, ok: false };
      childRows.push([parent + "." + kv[0], fmValue(kv[1])]);
      i++;
    }
    if (!sawIndent) return { rows: [], next: start, ok: true };
    if (listItems.length && childRows.length) return { rows: [], next: start, ok: false };
    if (listItems.length) {
      var joined = listItems.map(fmEsc).join(", ") || "&nbsp;";
      return { rows: [[parent, joined]], next: i, ok: true };
    }
    return { rows: childRows, next: i, ok: true };
  }

  function fmTable(block) {
    var rows = [], i = 0;
    while (i < block.length) {
      var line = block[i];
      if (line.trim() === "") { i++; continue; }
      if (/^\s/.test(line)) return null;
      var kv = fmSplitKV(line);
      if (!kv) return null;
      if (kv[1].trim() === "") {
        var c = fmChildren(block, i + 1, kv[0]);
        if (!c.ok) return null;
        if (c.rows.length) { rows = rows.concat(c.rows); i = c.next; continue; }
        rows.push([kv[0], "&nbsp;"]);
        i++;
        continue;
      }
      rows.push([kv[0], fmValue(kv[1])]);
      i++;
    }
    if (!rows.length) return null;
    var out = ['<table class="sd-frontmatter">',
      '<colgroup><col class="sd-fm-col-key"><col class="sd-fm-col-val"></colgroup>',
      "<tbody>"];
    rows.forEach(function (r) {
      out.push('<tr><td class="sd-fm-key">' + fmEsc(r[0]) + '</td><td class="sd-fm-val">' + r[1] + "</td></tr>");
    });
    out.push("</tbody></table>");
    return out.join("\n");
  }

  // { html, rest }: table (or fence fallback) for a leading --- block, remaining markdown.
  function splitFrontmatter(src) {
    var lines = src.split("\n");
    if (!lines.length || lines[0].replace(/\r$/, "") !== "---") return { html: "", rest: src };
    var close = -1;
    for (var i = 1; i < lines.length; i++) {
      var s = lines[i].replace(/\r$/, "");
      if (s === "---" || s === "...") { close = i; break; }
    }
    if (close < 0) return { html: "", rest: src };
    var block = lines.slice(1, close).map(function (l) { return l.replace(/\r$/, ""); });
    var rest = lines.slice(close + 1).join("\n");
    var table = null;
    try { table = fmTable(block); } catch (e) { table = null; }
    if (table !== null) return { html: table, rest: rest };
    return { html: global.marked.parse(["```yaml"].concat(block, "```").join("\n")), rest: rest };
  }

  function renderMath(src) {
    var blocks = [];
    function stash(html) {
      blocks.push(html);
      return "SDMATHPLACEHOLDER" + (blocks.length - 1) + "ENDSD";
    }
    // display first so the inline pass cannot eat half of a $$ pair
    src = src.replace(/\$\$([\s\S]+?)\$\$/g, function (whole, tex) {
      try {
        return stash(global.katex.renderToString(tex.trim(), { displayMode: true, throwOnError: false }));
      } catch (e) { return whole; }
    });
    // Inline $...$ with pandoc's currency-safe rule: non-space right after the opening $,
    // non-space right before the closing $, and the closing $ not followed by a digit, so
    // "$5K ... $930K" stays prose. A "|" in the candidate is excluded too: real inline TeX
    // with a pipe is rare, while unmatched dollars inside one table row are common.
    src = src.replace(/\$(?=\S)([^$\n|]*[^$\n|\s])\$(?!\d)/g, function (whole, tex) {
      try {
        return stash(global.katex.renderToString(tex.trim(), { displayMode: false, throwOnError: false }));
      } catch (e) { return whole; }
    });
    return { src: src, blocks: blocks };
  }

  // Obsidian/GitHub callouts: "> [!type] optional title" + following "> ..." lines.
  // Marked knows nothing about them, so stash the marker before parse and rewrite the
  // enclosing <blockquote> after parse. Unknown types get the note styling.
  var FM_CALLOUT_TYPES = { note: 1, tip: 1, important: 1, warning: 1, caution: 1 };

  function renderCallouts(src) {
    var outs = [];
    src = src.replace(/^([ \t]*>[ \t]*)\[!([A-Za-z]+)\][ \t]*(.*)$/gm, function (whole, prefix, type, title) {
      outs.push({ type: type.toLowerCase(), title: title.trim() });
      return prefix + "SDCALLOUT" + (outs.length - 1) + "ENDSD";
    });
    return { src: src, outs: outs };
  }

  function calloutHTML(html, outs) {
    return html.replace(/<blockquote>(\s*)<p>SDCALLOUT(\d+)ENDSD\s*/g, function (whole, ws, i) {
      var c = outs[+i];
      if (!c) return whole;
      var type = FM_CALLOUT_TYPES[c.type] ? c.type : "note";
      var label = c.type.charAt(0).toUpperCase() + c.type.slice(1).toLowerCase();
      var head = '<p class="sd-callout-head">' + fmEsc(label) +
        (c.title ? '<span class="sd-callout-title"> · ' + fmEsc(c.title) + "</span>" : "") + "</p>";
      return '<blockquote class="sd-callout sd-callout-' + type + '">' + ws + head + "<p>";
    }).replace(/<p>\s*<\/p>/g, "");
  }

  // Appex-only CSS: hide the double marker on task-list items (marked emits
  // <li><input...>). Callout accents live in the shared vscode-preview-head.html,
  // which build-safari.sh copies in as md-style.html.
  var QL_EXTRA_CSS = '<style>li.task-list-item{list-style:none}' +
    '.wikilink{text-decoration:underline dotted;text-underline-offset:.18em}</style>';

  // Obsidian wikilinks, [[target]] and [[target|title]], as a marked inline extension so
  // code spans and fences keep their brackets. The panel has nowhere to navigate, so a
  // wikilink renders as marked-up text rather than a dead link.
  function escapeText(s) {
    return s.replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  if (global.marked && !global.__sdWikilinks) {
    global.__sdWikilinks = true;
    global.marked.use({
      extensions: [{
        name: "wikilink",
        level: "inline",
        start: function (src) { var i = src.indexOf("[["); return i < 0 ? undefined : i; },
        tokenizer: function (src) {
          var m = /^\[\[([^\[\]|\n]+)(?:\|([^\[\]\n]+))?\]\]/.exec(src);
          if (m) return { type: "wikilink", raw: m[0], text: (m[2] || m[1]).trim() };
        },
        renderer: function (token) { return '<span class="wikilink">' + escapeText(token.text) + "</span>"; }
      }]
    });
  }

  // Syntax highlighting. The pandoc path highlights via `--syntax-highlighting tango`,
  // so an unhighlighted panel read as a downgrade from the browser preview. Done as a
  // string pass over marked's output rather than a marked plugin, which keeps this
  // independent of marked's changing highlight API and stays DOM-free for JavaScriptCore.
  var UNESC = { "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&#39;": "'" };

  function unescapeHTML(s) {
    return s.replace(/&(amp|lt|gt|quot|#39);/g, function (m) { return UNESC[m]; });
  }

  function highlightBlocks(html) {
    if (!global.hljs) return html;
    return html.replace(
      /<pre><code class="language-([\w+#.-]+)">([\s\S]*?)<\/code><\/pre>/g,
      function (whole, lang, body) {
        if (!global.hljs.getLanguage(lang)) return whole;
        try {
          var out = global.hljs.highlight(unescapeHTML(body), { language: lang }).value;
          return '<pre><code class="hljs language-' + lang + '">' + out + "</code></pre>";
        } catch (e) {
          return whole;
        }
      }
    );
  }

  // Auto table layout sizes a column by its longest WORD when a prose column is
  // competing for the width, so a short "Date" column collapses and "1960s to 1970s"
  // wraps over three lines. Mark short columns so the CSS can keep them on one line.
  // Done here, at render time, because the panel runs no scripts (its CSP denies them).
  var TIGHT_MAX = 16;   // longest cell, in characters, that still counts as short
  var TIGHT_BUDGET = 40; // total tight characters per table, so a wide table still wraps
  var NARROW_MAX = 34;  // a label column: too long to hold on one line, too short to earn a prose share
  // Width budget for a table that no longer fits the reading column. Wider than the
  // column itself, which is what puts the table on a horizontal scroll.
  var WIDE_TOTAL = 100; // characters shared out across the non-tight columns
  var COL_MIN = 22;     // below this a prose cell reads as a word ladder
  var COL_MAX = 52;     // above this the line is too long to track back

  function cellText(html) {
    return unescapeHTML(html.replace(/<[^>]*>/g, "")).trim();
  }

  function tightColumns(html) {
    return html.replace(/<table>[\s\S]*?<\/table>/g, function (table) {
      var widths = [];
      var rows = table.match(/<tr>[\s\S]*?<\/tr>/g) || [];
      var cols = 0;
      rows.forEach(function (row) {
        var i = 0;
        row.replace(/<(t[hd])\b[^>]*>([\s\S]*?)<\/\1>/g, function (whole, tag, body) {
          widths[i] = Math.max(widths[i] || 0, cellText(body).length);
          i++;
          return whole;
        });
        cols = Math.max(cols, i);
      });
      // A prose column is what squeezes the others. With none, no column needs help.
      var hasProse = widths.some(function (w) { return w > NARROW_MAX; });
      var spent = 0;
      var classes = widths.map(function (w) {
        if (!hasProse) return "";
        if (w <= TIGHT_MAX && spent + w <= TIGHT_BUDGET) { spent += w; return "sd-tight"; }
        if (w <= NARROW_MAX) return "sd-narrow";
        return "";
      });
      // Two prose columns split the width by how much text each holds, so the shorter
      // one ends up a few words wide. Four columns run out of room whatever they hold.
      // Either way the table stops fitting the reading column, so give each column a
      // floor sized to its own content and let the table scroll sideways.
      var wide = cols >= 4 || widths.filter(function (w) { return w > NARROW_MAX; }).length >= 2;
      var floors = [];
      if (wide) {
        table = table.replace("<table>", '<table class="sd-wide">');
        // A cell of length L wrapped at width W is L/W lines tall, so widths in
        // proportion to content are what make the columns of a row end level.
        var share = widths.reduce(function (sum, w, i) {
          return sum + (classes[i] === "sd-tight" ? 0 : w);
        }, 0);
        floors = widths.map(function (w, i) {
          if (classes[i] === "sd-tight" || !share) return 0;
          var ch = Math.round((w / share) * WIDE_TOTAL);
          return Math.min(COL_MAX, Math.max(COL_MIN, ch));
        });
      }
      if (!classes.some(Boolean) && !wide) return table;
      return table.replace(/<tr>[\s\S]*?<\/tr>/g, function (row) {
        var i = 0;
        return row.replace(/<(t[hd])(\b[^>]*)>/g, function (whole, tag, attrs) {
          var cls = classes[i];
          var floor = floors[i];
          i++;
          if (cls) attrs += ' class="' + cls + '"';
          if (floor) attrs += ' style="min-width:' + floor + 'ch"';
          return cls || floor ? "<" + tag + attrs + ">" : whole;
        });
      });
    });
  }

  // cfg: optional settings object (see SD.config below); plugins get it validated.
  function mdToHtml(src, cfg) {
    var fm = splitFrontmatter(String(src == null ? "" : src));
    var co = renderCallouts(fm.rest);
    var m = renderMath(co.src);
    // breaks:true = Obsidian's default (single newline -> <br>), so multi-line
    // blockquotes/callouts keep their authored line structure instead of joining
    // into one paragraph. Matches the pandoc path's +hard_line_breaks.
    var html = global.marked.parse(m.src, { breaks: true });
    // Highlight BEFORE math is substituted back. The other order let hljs unescape and
    // re-escape whole KaTeX spans that sat inside a fence, filling the code block with
    // tag soup: `$x$` in a js fence became about 1.5KB of escaped markup.
    html = highlightBlocks(html);
    html = html.replace(/SDMATHPLACEHOLDER(\d+)ENDSD/g, function (whole, i) {
      var b = m.blocks[+i];
      return b == null ? whole : b;
    });
    html = calloutHTML(html, co.outs);
    html = tightColumns(html);
    html = html.replace(/<li>(\s*)<input /g, '<li class="task-list-item">$1<input ');
    html = runTransforms(fm.html ? fm.html + "\n" + html : html, config(cfg));
    return QL_EXTRA_CSS + "\n" + html;
  }

  // ---- Plug-in registry and settings (frozen contract: docs/contract-r1.md) ----
  // A feature that is not core rendering (X-ray, Present) lives in its own file, loaded
  // after this one, and calls SD.register. Two kinds of hook:
  //   render time, DOM-free, return strings: transform, css, controls, toolbar. These run
  //     everywhere the core runs (JavaScriptCore in the appex, node, osascript).
  //   page time, need a live DOM: init, key, print, reset. They run only where the page
  //     executes scripts, through SD.boot(document, cfg). The Quick Look panel does not.
  // A hook that throws is skipped and logged to SD.errors; it never breaks the render.

  // Settings: keys, types and defaults. The app writes these to the App Group defaults
  // suite; SpacedownSettings.swift mirrors this table and the quicklook smoke section
  // fails when the two drift.
  var DEFAULTS = {
    theme: "ia",
    appearance: "system",
    textSize: 18,
    outlineDefault: "auto",
    xrayEnabled: false,
    xrayDashes: true,
    xrayLongSentences: true,
    xraySentenceWords: 25,
    xrayFillers: true,
    xrayFillerWords: ["very", "really", "just", "actually", "basically", "simply", "quite",
      "rather", "somewhat", "literally", "obviously", "clearly", "of course", "in order to"],
    xrayTicketIds: true
  };
  var ENUMS = {
    theme: ["ia", "tm", "paper", "read", "mono"],
    appearance: ["system", "light", "dark"],
    outlineDefault: ["auto", "open", "closed"]
  };
  var RANGES = { textSize: [12, 32], xraySentenceWords: [8, 80] };
  var SURFACES = ["quicklook", "cli", "app", "test"];

  function copyValue(v) { return Array.isArray(v) ? v.slice() : v; }

  // One validated value for key k, or undefined when v does not fit the key's type.
  function validValue(k, v) {
    var d = DEFAULTS[k];
    if (Array.isArray(d)) {
      if (!Array.isArray(v)) return undefined;
      return v.filter(function (x) { return typeof x === "string" && x.trim() !== ""; })
        .map(function (x) { return x.trim(); });
    }
    if (typeof d === "boolean") {
      if (typeof v === "boolean") return v;
      if (v === 0 || v === 1) return v === 1; // NSNumber bools can bridge as 0/1
      return undefined;
    }
    if (typeof d === "number") {
      if (typeof v !== "number" || !isFinite(v)) return undefined;
      var r = RANGES[k];
      return Math.min(r[1], Math.max(r[0], Math.round(v)));
    }
    if (typeof v !== "string") return undefined;
    return ENUMS[k] && ENUMS[k].indexOf(v) < 0 ? undefined : v;
  }

  // Full settings object: DEFAULTS overlaid with every valid key of `partial`. Unknown
  // keys and wrong types are dropped. `surface` says which host renders.
  function config(partial) {
    var out = {}, k;
    for (k in DEFAULTS) out[k] = copyValue(DEFAULTS[k]);
    out.surface = "quicklook";
    if (!partial || typeof partial !== "object") return out;
    for (k in DEFAULTS) {
      if (!Object.prototype.hasOwnProperty.call(partial, k)) continue;
      var v = validValue(k, partial[k]);
      if (v !== undefined) out[k] = v;
    }
    if (SURFACES.indexOf(partial.surface) >= 0) out.surface = partial.surface;
    return out;
  }

  var plugins = [];
  var errors = [];

  function register(plugin) {
    if (!plugin || typeof plugin.id !== "string" || plugin.id === "") {
      throw new Error("SD.register: a plugin needs a string id");
    }
    plugins = plugins.filter(function (p) { return p.id !== plugin.id; });
    plugins.push(plugin);
    // Lower order runs first; equal order keeps registration order (stable sort).
    plugins.sort(function (a, b) { return (a.order || 100) - (b.order || 100); });
    return plugin;
  }

  // Call hook on every plugin that has it; fn(plugin) does the call. Errors are logged.
  function each(hook, fn) {
    plugins.slice().forEach(function (p) {
      if (typeof p[hook] !== "function") return;
      try { fn(p); } catch (e) { errors.push(p.id + "." + hook + ": " + (e && e.message || e)); }
    });
  }

  function runTransforms(html, cfg) {
    each("transform", function (p) {
      var out = p.transform(html, cfg);
      if (typeof out === "string") html = out;
    });
    return html;
  }

  function collect(hook, cfg) {
    var parts = [];
    each(hook, function (p) {
      var s = p[hook](cfg);
      if (typeof s === "string" && s !== "") parts.push(s);
    });
    return parts.join("\n");
  }

  // The shared toolbar: fixed top right, hidden in print. Plugins only add items to it.
  var TOOLBAR_CSS = ".sd-ql-toolbar{position:fixed;top:10px;right:12px;z-index:10;display:flex;" +
    "gap:4px;font:12px -apple-system,sans-serif}@media print{.sd-ql-toolbar{display:none}}";

  // The page's top-of-body chrome: every plugin's controls (body-level, before the
  // content, so a CSS sibling selector can reach the document), then the toolbar.
  function chrome(cfg, items) {
    var bar = items ? '<div class="sd-ql-toolbar" role="toolbar" aria-label="Preview tools">' +
      items + "</div>" : "";
    var controls = collect("controls", cfg);
    return controls && bar ? controls + "\n" + bar : controls + bar;
  }

  // Attributes for the <html> element: settings the page CSS keys off.
  function htmlAttrs(cfg) {
    return 'data-sd-theme="' + escapeText(cfg.theme) + '" data-sd-appearance="' +
      escapeText(cfg.appearance) + '" data-sd-outline="' + escapeText(cfg.outlineDefault) +
      '" style="--ql-size:' + cfg.textSize + 'px"';
  }

  // Everything a host needs to build the page, DOM-free.
  function render(src, partial) {
    var cfg = config(partial);
    var items = collect("toolbar", cfg);
    var css = collect("css", cfg);
    return {
      body: mdToHtml(src, cfg),
      css: items ? TOOLBAR_CSS + (css ? "\n" + css : "") : css,
      chrome: chrome(cfg, items),
      attrs: htmlAttrs(cfg),
      config: cfg
    };
  }

  // Page time: call init, route keys, run print. Only in a page that runs scripts.
  function boot(doc, partial) {
    var cfg = config(partial);
    each("init", function (p) { p.init(doc, cfg); });
    doc.addEventListener("keydown", function (ev) {
      if (ev.defaultPrevented || ev.metaKey || ev.ctrlKey || ev.altKey) return;
      var t = ev.target;
      if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName || ""))) return;
      var handled = false;
      each("key", function (p) { if (!handled && p.key(ev, cfg) === true) handled = true; });
      if (handled && ev.preventDefault) ev.preventDefault();
    });
    var win = doc.defaultView;
    if (win && win.addEventListener) {
      win.addEventListener("beforeprint", function () { each("print", function (p) { p.print(doc, cfg); }); });
    }
    return cfg;
  }

  // Back to the plain reading page: every plugin undoes its page state.
  function reset(doc, partial) {
    var cfg = config(partial);
    each("reset", function (p) { p.reset(doc, cfg); });
  }

  global.SD = {
    contract: 1,
    DEFAULTS: DEFAULTS,
    ENUMS: ENUMS,
    RANGES: RANGES,
    config: config,
    register: register,
    plugins: function () { return plugins.map(function (p) { return p.id; }); },
    plugin: function (id) { return plugins.filter(function (p) { return p.id === id; })[0] || null; },
    errors: errors,
    render: render,
    boot: boot,
    reset: reset
  };
  global.mdToHtml = mdToHtml;
})(typeof globalThis !== "undefined" ? globalThis : this);

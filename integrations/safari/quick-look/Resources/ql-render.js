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
  // The .mdp-frontmatter CSS ships in md-style.html already. Omitted vs the python:
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
    if (FM_SCALAR_RE.test(v)) return '<span class="mdp-fm-scalar">' + fmEsc(v) + "</span>";
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
    var out = ['<table class="mdp-frontmatter">',
      '<colgroup><col class="mdp-fm-col-key"><col class="mdp-fm-col-val"></colgroup>',
      "<tbody>"];
    rows.forEach(function (r) {
      out.push('<tr><td class="mdp-fm-key">' + fmEsc(r[0]) + '</td><td class="mdp-fm-val">' + r[1] + "</td></tr>");
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
      return "MDPMATHPLACEHOLDER" + (blocks.length - 1) + "ENDMDP";
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
      return prefix + "MDPCALLOUT" + (outs.length - 1) + "ENDMDP";
    });
    return { src: src, outs: outs };
  }

  function calloutHTML(html, outs) {
    return html.replace(/<blockquote>(\s*)<p>MDPCALLOUT(\d+)ENDMDP\s*/g, function (whole, ws, i) {
      var c = outs[+i];
      if (!c) return whole;
      var type = FM_CALLOUT_TYPES[c.type] ? c.type : "note";
      var label = c.type.charAt(0).toUpperCase() + c.type.slice(1).toLowerCase();
      var head = '<p class="mdp-callout-head">' + fmEsc(label) +
        (c.title ? '<span class="mdp-callout-title"> · ' + fmEsc(c.title) + "</span>" : "") + "</p>";
      return '<blockquote class="mdp-callout mdp-callout-' + type + '">' + ws + head + "<p>";
    }).replace(/<p>\s*<\/p>/g, "");
  }

  // Appex-only CSS: hide the double marker on task-list items (marked emits
  // <li><input...>). Callout accents live in the shared vscode-preview-head.html,
  // which build-safari.sh copies in as md-style.html.
  var QL_EXTRA_CSS = '<style>li.task-list-item{list-style:none}</style>';

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
        if (w <= TIGHT_MAX && spent + w <= TIGHT_BUDGET) { spent += w; return "mdp-tight"; }
        if (w <= NARROW_MAX) return "mdp-narrow";
        return "";
      });
      // Two prose columns split the width by how much text each holds, so the shorter
      // one ends up a few words wide. Four columns run out of room whatever they hold.
      // Either way the table stops fitting the reading column, so give each column a
      // floor sized to its own content and let the table scroll sideways.
      var wide = cols >= 4 || widths.filter(function (w) { return w > NARROW_MAX; }).length >= 2;
      var floors = [];
      if (wide) {
        table = table.replace("<table>", '<table class="mdp-wide">');
        // A cell of length L wrapped at width W is L/W lines tall, so widths in
        // proportion to content are what make the columns of a row end level.
        var share = widths.reduce(function (sum, w, i) {
          return sum + (classes[i] === "mdp-tight" ? 0 : w);
        }, 0);
        floors = widths.map(function (w, i) {
          if (classes[i] === "mdp-tight" || !share) return 0;
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

  function mdToHtml(src) {
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
    html = html.replace(/MDPMATHPLACEHOLDER(\d+)ENDMDP/g, function (whole, i) {
      var b = m.blocks[+i];
      return b == null ? whole : b;
    });
    html = calloutHTML(html, co.outs);
    html = tightColumns(html);
    html = html.replace(/<li>(\s*)<input /g, '<li class="task-list-item">$1<input ');
    return QL_EXTRA_CSS + "\n" + (fm.html ? fm.html + "\n" + html : html);
  }

  global.mdToHtml = mdToHtml;
})(typeof globalThis !== "undefined" ? globalThis : this);

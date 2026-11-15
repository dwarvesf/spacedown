// sd-cli-render.js: the spacedown CLI's HTML renderer. Runs under `osascript -l JavaScript`
// (bin/spacedown calls it), loads the Quick Look core in Resources/load-order.txt order, calls
// SD.render, and builds the browser page around it. No pandoc, no python.
//
//   osascript -l JavaScript assets/sd-cli-render.js root=... resources=... src=... out=... [key=value ...]
//
// Options, as key=value arguments (bin/spacedown builds them): root (the dir holding assets/),
// resources (the Quick Look Resources dir: the repo copy, or the app's own extension), src,
// out, title, fontMode (becomes the core's theme setting), themeOverride (a CSS file),
// standalone, livereload, embedImages, embedFonts, absImages, mathAs ("tex" = plain TeX, for
// docx), settings (the JSON scripts/sd-settings prints), vscodeSettings (a settings.json),
// lintOut (a path: also write the Writing X-ray findings there as JSON; see lintFindings).
// Diagnostics go to stderr through console.log; the page is written to `out`.
// Page contract: docs/contract-r1.md (host order), README "CLI".
ObjC.import("Foundation");

function run(argv) {
  var opt = {};
  argv.forEach(function (a) { var i = a.indexOf("="); if (i > 0) opt[a.slice(0, i)] = a.slice(i + 1); });
  opt.settings = opt.settings ? JSON.parse(opt.settings) : {};
  ["standalone", "livereload", "embedImages", "embedFonts", "absImages"].forEach(function (k) { opt[k] = opt[k] === "1"; });
  var FM = $.NSFileManager.defaultManager;

  function readText(path) {
    var s = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
    return s ? ObjC.unwrap(s) : null;
  }
  function must(path) {
    var s = readText(path);
    if (s === null) throw new Error("cannot read " + path);
    return s;
  }
  function base64Of(path) {
    var d = $.NSData.dataWithContentsOfFile(path);
    return d ? ObjC.unwrap(d.base64EncodedStringWithOptions(0)) : null;
  }
  function isFile(path) {
    var dir = Ref();
    return FM.fileExistsAtPathIsDirectory(path, dir) && !dir[0];
  }
  function fileSize(path) {
    var a = FM.attributesOfItemAtPathError(path, null);
    return a ? Number(ObjC.unwrap(a.objectForKey("NSFileSize"))) : 0;
  }
  function log(msg) { console.log("spacedown: " + msg); }
  function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
  function escAttr(s) { return esc(s).replace(/"/g, "&quot;"); }

  var ROOT = opt.root;
  var RES = opt.resources;
  var ASSETS = ROOT + "/assets";

  // ---- load the core, in the order the one shared list names ----
  var order = must(RES + "/load-order.txt").split("\n").map(function (l) { return l.trim(); })
    .filter(function (l) { return l && l.charAt(0) !== "#"; });
  var pageScripts = [];
  var VENDOR = { "marked.min.js": 1, "katex.min.js": 1, "highlight.min.js": 1 };
  order.forEach(function (f) {
    var text = must(RES + "/" + f);
    (0, eval)(text);
    // The page itself needs only the registry and the plug-ins (SD.boot), not the engines.
    if (!VENDOR[f]) pageScripts.push(text);
  });

  // ---- protect literal text from the core's math and callout passes ----
  // ql-render.js reads a $ or a [!note] inside code as math or a callout. Swap them for
  // private-use characters on the way in and back on the way out; the highlighter is wrapped
  // so it sees the real characters.
  var DOLLAR = "\uE000", BRACKET = "\uE001";
  function guard(s) { return s.replace(/\$/g, DOLLAR); }
  function unguard(s) { return s.replace(/\uE000/g, "$").replace(/\uE001/g, "["); }
  if (typeof hljs !== "undefined" && hljs.highlight) {
    var highlight = hljs.highlight;
    hljs.highlight = function (code, o) { return highlight.call(hljs, unguard(code), o); };
  }

  function protectCode(src) {
    var lines = src.split("\n"), out = [], fence = null;
    lines.forEach(function (line) {
      var m = /^ {0,3}(`{3,}|~{3,})/.exec(line);
      if (m) {
        var mark = m[1];
        if (fence === null) fence = mark;
        else if (mark.charAt(0) === fence.charAt(0) && mark.length >= fence.length && /^ {0,3}[`~]+\s*$/.test(line)) fence = null;
        out.push(guard(line));
        return;
      }
      if (fence !== null) {
        out.push(guard(line).replace(/^([ \t]*>[ \t]*)\[!/, function (w, p) { return p + BRACKET + "!"; }));
        return;
      }
      // inline code spans, then an escaped dollar
      line = line.replace(/(`+)([^`]|[^`][\s\S]*?[^`])\1(?!`)/g, function (w) { return guard(w); });
      line = line.replace(/\\\$/g, DOLLAR);
      out.push(line);
    });
    return out.join("\n");
  }

  // ---- source pre-passes (ports of assets/eq-labels.py and assets/tsv-tables.py) ----
  function csvRows(text, delim) {
    var rows = [], row = [], cell = "", q = false, i, c;
    for (i = 0; i < text.length; i++) {
      c = text.charAt(i);
      if (q) {
        if (c === '"' && text.charAt(i + 1) === '"') { cell += '"'; i++; }
        else if (c === '"') q = false;
        else cell += c;
      } else if (c === '"' && cell === "") q = true;
      else if (c === delim) { row.push(cell); cell = ""; }
      else if (c === "\n") { row.push(cell); rows.push(row); row = []; cell = ""; }
      else if (c !== "\r") cell += c;
    }
    row.push(cell); rows.push(row);
    return rows.filter(function (r) { return r.some(function (x) { return x.trim() !== ""; }); });
  }

  function dataTable(text, delim) {
    var rows = csvRows(text, delim);
    if (!rows.length) return null;
    var width = Math.max.apply(null, rows.map(function (r) { return r.length; }));
    var out = '<div class="sd-scroll"><table class="sd-data"><tbody>';
    rows.forEach(function (r) {
      while (r.length < width) r.push("");
      out += "<tr>" + r.map(function (c) { return "<td>" + esc(c.trim()) + "</td>"; }).join("") + "</tr>";
    });
    return out + "</tbody></table></div>";
  }

  // Footnotes, [^id] with a [^id]: text definition (marked has none): the reference becomes a
  // superscript link in order of first use, the notes close the page in a section.footnotes.
  function footnotes(src) {
    var lines = src.split("\n"), kept = [], fence = null, defs = {}, i = 0, m;
    var DEF = /^ {0,3}\[\^([^\]\s]+)\]:[ \t]*(.*)$/;
    function fenceLine(line) {
      var f = /^ {0,3}(`{3,}|~{3,})/.exec(line);
      if (!f) return false;
      if (fence === null) fence = f[1];
      else if (f[1].charAt(0) === fence.charAt(0) && f[1].length >= fence.length) fence = null;
      return true;
    }
    while (i < lines.length) {
      if (fenceLine(lines[i])) { kept.push(lines[i++]); continue; }
      if (fence === null && (m = DEF.exec(lines[i]))) {
        var text = [m[2]];
        i++;
        while (i < lines.length && /^(?: {2,}|\t)\S/.test(lines[i])) text.push(lines[i++].trim());
        defs[m[1]] = text.join(" ");
        continue;
      }
      kept.push(lines[i++]);
    }
    var numbers = {}, order = [];
    fence = null;
    var out = kept.map(function (line) {
      if (fenceLine(line) || fence !== null || line.indexOf("[^") < 0) return line;
      var codes = [];
      line = line.replace(/(`+)([^`]|[^`][\s\S]*?[^`])\1(?!`)/g, function (w) { codes.push(w); return "\uE002" + (codes.length - 1) + "\uE002"; });
      line = line.replace(/\[\^([^\]\s]+)\]/g, function (w, id) {
        if (!Object.prototype.hasOwnProperty.call(defs, id)) return w;
        var first = !Object.prototype.hasOwnProperty.call(numbers, id);
        if (first) { order.push(id); numbers[id] = order.length; }
        var n = numbers[id];
        return '<a href="#fn' + n + '" class="footnote-ref"' + (first ? ' id="fnref' + n + '"' : "") +
          ' role="doc-noteref"><sup>' + n + "</sup></a>";
      });
      return line.replace(/\uE002(\d+)\uE002/g, function (w, k) { return codes[+k]; });
    });
    var html = "";
    if (order.length) {
      html = '<section id="footnotes" class="footnotes footnote-section" role="doc-endnotes">\n<hr>\n<ol>\n';
      order.forEach(function (id, k) {
        var n = k + 1;
        html += '<li id="fn' + n + '"><p>' + marked.parseInline(defs[id]) + ' <a href="#fnref' + n +
          '" class="footnote-back" role="doc-backlink">\u21a9\uFE0E</a></p></li>\n';
      });
      html += "</ol>\n</section>";
    }
    return { src: out.join("\n"), html: html };
  }

  var EQ_RE = /^(\s*)\$\$(?!\$)(.+?)\$\$[ \t]*\{#([A-Za-z][A-Za-z0-9_:.-]*)\}[ \t]*$/;
  function prePasses(src) {
    var lines = src.split("\n"), out = [], fence = null, tsv = null, number = 0;
    lines.forEach(function (line) {
      var body = line.replace(/\r$/, "");
      var m = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(body);
      if (m) {
        var mark = m[1];
        if (fence === null) {
          fence = mark;
          var kind = m[2].trim().split(/\s+/)[0];
          if (kind === "tsv" || kind === "csv") { tsv = { kind: kind, rows: [] }; return; }
        } else if (mark.charAt(0) === fence.charAt(0) && mark.length >= fence.length && m[2].trim() === "") {
          fence = null;
          if (tsv) {
            var html = dataTable(tsv.rows.join("\n"), tsv.kind === "tsv" ? "\t" : ",");
            if (html) out.push("", html, "");
            else out.push("```" + tsv.kind, tsv.rows.join("\n"), "```");
            tsv = null;
            return;
          }
        }
        out.push(line);
        return;
      }
      if (tsv) { tsv.rows.push(body); return; }
      var eq = fence === null ? EQ_RE.exec(body) : null;
      if (!eq) { out.push(line); return; }
      var formula = eq[2].trim();
      if (formula.indexOf("\\tag") < 0) { number++; formula += " \\tag{" + number + "}"; }
      out.push(eq[1] + '<div class="sd-eq" id="' + eq[3] + '">', "", "$$ " + formula + " $$", "", "</div>");
    });
    return out.join("\n");
  }

  // ---- body post-passes ----
  function plain(html) {
    return html.replace(/<[^>]*>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'").replace(/&amp;/g, "&");
  }

  // pandoc's identifier rule: letters, digits, _ - . kept; spaces to hyphens; leading
  // non-letters dropped; "section" when nothing is left; repeats get -1, -2.
  function headingIds(html) {
    var seen = {}, toc = [];
    html = html.replace(/<h([1-6])>([\s\S]*?)<\/h\1>/g, function (whole, level, inner) {
      var base = plain(inner).toLowerCase().replace(/[^\p{L}\p{N}_\-.\s]/gu, "").trim()
        .replace(/\s+/g, "-").replace(/^[^\p{L}]+/u, "") || "section";
      var id = base, n = 0;
      while (seen[id]) { n++; id = base + "-" + n; }
      seen[id] = 1;
      toc.push({ level: +level, id: id, html: inner.replace(/<\/?a\b[^>]*>/g, "") });
      return "<h" + level + ' id="' + id + '">' + inner + "</h" + level + ">";
    });
    return { html: html, toc: toc };
  }

  // pandoc's --toc-depth=4 outline, as nav#TOC (the reading chrome keys off it).
  function tocNav(toc) {
    toc = toc.filter(function (h) { return h.level <= 4; });
    if (!toc.length) return "";
    var out = '<nav id="TOC" role="doc-toc">\n', stack = [], i;
    toc.forEach(function (h) {
      var top = stack.length ? stack[stack.length - 1] : 0;
      if (!stack.length) { out += "<ul>\n"; stack.push(h.level); }
      else if (h.level > top) { out += "\n<ul>\n"; stack.push(h.level); }
      else {
        out += "</li>\n";
        while (stack.length > 1 && h.level < stack[stack.length - 1]) { stack.pop(); out += "</ul>\n</li>\n"; }
      }
      out += '<li><a href="#' + h.id + '" id="toc-' + h.id + '">' + h.html + "</a>";
    });
    out += "</li>\n";
    for (i = stack.length - 1; i > 0; i--) out += "</ul>\n</li>\n";
    return out + "</ul>\n</nav>";
  }

  // marked puts a highlighted fence in a bare <pre><code>; the page CSS is written for the
  // div.sourceCode > pre.sourceCode > code.sourceCode shape.
  function wrapCode(html) {
    var n = 0;
    return html.replace(/<pre><code class="((?:hljs )?language-([\w+#.-]+))">([\s\S]*?)<\/code><\/pre>/g,
      function (whole, cls, lang, body) {
        n++;
        return '<div class="sourceCode" id="cb' + n + '"><pre class="sourceCode ' + lang + '"><code class="sourceCode ' +
          lang + " " + cls + '">' + body + "</code></pre></div>";
      });
  }

  // A long frontmatter value gets the clamp, an explicit (1) (2) (3) run breaks onto lines
  // (ports of the python table renderer's two extras; the core omits them).
  var ENUM_RE = /\s+(\(\d+\))\s/g;
  function frontmatterExtras(html) {
    return html.replace(/<table class="sd-frontmatter">([\s\S]*?)<\/table>/g, function (whole, inner) {
      var long = false;
      inner = inner.replace(/<tr><td class="sd-fm-key">([\s\S]*?)<\/td><td class="sd-fm-val">([\s\S]*?)<\/td><\/tr>/g,
        function (row, key, val) {
          if ((val.match(ENUM_RE) || []).length >= 2) {
            var k = 0;
            val = val.replace(ENUM_RE, function (w, marker) { k++; return k === 1 ? w : "<br>" + marker + " "; });
          }
          if (plain(val).trim().length >= 160) {
            long = true;
            return '<tr class="sd-fm-row-stacked"><td class="sd-fm-key">' + key +
              '</td><td class="sd-fm-val sd-fm-long"><div class="sd-fm-clamp">' + val + "</div></td></tr>";
          }
          return '<tr><td class="sd-fm-key">' + key + '</td><td class="sd-fm-val">' + val + "</td></tr>";
        });
      return '<table class="' + (long ? "sd-frontmatter sd-fm-has-long" : "sd-frontmatter") + '">' + inner + "</table>";
    });
  }

  // The core's column hints (sd-wide, sd-tight, sd-narrow, min-width floors) are laid out by
  // ql-reading.css, which only the Quick Look panel loads, so the page drops them. A column's
  // alignment moves from the align attribute, which a theme's text-align beats, to a style.
  function tableAttrs(html) {
    html = html.replace(/<table class="sd-wide">/g, "<table>");
    return html.replace(/<(t[hd])\b([^>]*)>/g, function (whole, tag, attrs) {
      attrs = attrs.replace(/ class="sd-(?:tight|narrow)"/g, "").replace(/ style="min-width:\d+ch"/g, "");
      var align = /\salign="(left|right|center)"/.exec(attrs);
      if (align) {
        attrs = attrs.replace(align[0], "");
        attrs += ' style="text-align: ' + align[1] + ';"';
      }
      return "<" + tag + attrs + ">";
    });
  }

  // "> [!note] Title" then a line break: breaks:true leaves a <br> at the top of the body.
  function calloutBreak(html) {
    return html.replace(/(<p class="sd-callout-head">[\s\S]*?<\/p>\s*<p>)\s*<br\s*\/?>\s*/g, function (w, head) { return head; });
  }

  // A header with no rows gets one blank row, so it reads as a fill-in table.
  function blankRows(html) {
    return html.replace(/<table([^>]*)>\s*<thead>([\s\S]*?)<\/thead>\s*<\/table>/g, function (whole, attrs, head) {
      var cols = (head.match(/<th\b/g) || []).length || 1, cells = "";
      for (var i = 0; i < cols; i++) cells += "<td></td>";
      return "<table" + attrs + "><thead>" + head + "</thead><tbody><tr>" + cells + "</tr></tbody></table>";
    });
  }

  // ---- local images as data: URIs (port of assets/embed-images.py) ----
  var MAX_IMG = 5 * 1024 * 1024;
  var MIME = { svg: "image/svg+xml", png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg",
    gif: "image/gif", webp: "image/webp", avif: "image/avif" };
  var srcDir = opt.src.replace(/\/[^\/]*$/, "") || "/";
  var imgCache = {}, imgWidth = {}, warned = {};

  function embedTarget(target) {
    if (!target || target.indexOf("data:") === 0) return null;
    if (Object.prototype.hasOwnProperty.call(imgCache, target)) return imgCache[target];
    imgCache[target] = null;
    var path = target;
    if (/^file:/i.test(target)) path = target.replace(/^file:\/\/(localhost)?/i, "");
    else if (/^(?:[a-zA-Z][a-zA-Z0-9+.-]*:|\/\/)/.test(target)) return null;
    path = path.split("#")[0].split("?")[0];
    try { path = decodeURIComponent(path); } catch (e) { /* keep as written */ }
    if (path.charAt(0) !== "/") path = srcDir + "/" + path;
    var ext = (/\.([A-Za-z0-9]+)$/.exec(path) || [0, ""])[1].toLowerCase();
    if (!MIME[ext] || !isFile(path)) return null;
    var size = fileSize(path);
    if (size > MAX_IMG) {
      if (!warned[path]) { warned[path] = 1; log("image over 5 MB, not embedded: " + path + " (" + (size / 1048576).toFixed(1) + " MB)"); }
      return null;
    }
    var b64 = base64Of(path);
    if (b64 === null) return null;
    if (ext === "svg") {
      var head = readText(path);
      var m = head && /<svg\b[^>]*?\swidth\s*=\s*["']([0-9.]+)(?:px)?["']/i.exec(head.slice(0, 4096));
      if (m) imgWidth[target] = m[1];
    }
    imgCache[target] = "data:" + MIME[ext] + ";base64," + b64;
    return imgCache[target];
  }

  // docx fallback: textutil reads the images itself, so a local path becomes an absolute one
  function absTarget(target) {
    if (!target || /^(?:[a-zA-Z][a-zA-Z0-9+.-]*:|\/\/)/.test(target)) return null;
    var path = target;
    try { path = decodeURIComponent(path.split("#")[0].split("?")[0]); } catch (e) { return null; }
    if (path.charAt(0) !== "/") path = srcDir + "/" + path;
    return isFile(path) ? path : null;
  }

  function embedImages(html) {
    return html.replace(/<img\b[^>]*?>/gi, function (tag) {
      var m = /\bsrc\s*=\s*(["'])(.*?)\1/i.exec(tag);
      if (!m) return tag;
      var uri = opt.absImages ? absTarget(m[2]) : embedTarget(m[2]);
      if (!uri) return tag;
      var width = imgWidth[m[2]] && !/\swidth\s*=/i.test(tag) ? ' width="' + imgWidth[m[2]] + '"' : "";
      return tag.replace(m[0], function () { return "src=" + m[1] + uri + m[1] + width; });
    });
  }


  // ---- Writing X-ray findings as data (--lint-json; the MCP lint tool reads it) ----
  // The xray plug-in marks hits at render time as <span class="sd-xr sd-xr-RULE" title="X-ray, ...">.
  // Read those marks back out of the rendered body in document order, and give each a source
  // line: a forward search through the source with code and comments blanked out, so the same
  // dash or word in two places lands on the right lines. line is null when no match is found.
  var LINT_RULES = { dash: "dash", long: "long-sentence", filler: "filler", ticket: "ticket-id" };
  function unesc(s) { return s.replace(/&quot;/g, '"').replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&"); }
  function reEscape(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }
  function maskSource(src) {
    function blank(w) { return w.replace(/[^\n]/g, " "); }
    return src.replace(/^ {0,3}(`{3,}|~{3,})[^\n]*\n[\s\S]*?(?:\n {0,3}\1[`~]*[ \t]*(?=\n|$)|$)/gm, blank)
      .replace(/<!--[\s\S]*?-->/g, blank).replace(/(`+)[^\n]*?\1/g, blank);
  }
  function lintFindings(body, src) {
    var findings = [], stack = [], open = null, m, re = /<[^>]*>|[^<]+/g;
    while ((m = re.exec(body)) !== null) {
      var tok = m[0];
      if (tok.charAt(0) !== "<") {
        var text = unesc(tok);
        stack.forEach(function (e) { if (e) e.f.text += text; });
      } else if (/^<span\b/i.test(tok)) {
        var c = /class="sd-xr sd-xr-(\w+)"/.exec(tok), rule = c && LINT_RULES[c[1]];
        if (!rule) { stack.push(null); continue; }
        var title = /title="([^"]*)"/.exec(tok), last = /data-sd-words="\d+"/.test(tok), f;
        if (rule === "long-sentence" && open) f = open; // a later piece of the same sentence
        else {
          f = { rule: rule, text: "", message: unesc(title ? title[1] : "").replace(/^X-ray, /, "") };
          findings.push(f);
          if (rule === "long-sentence") open = f;
        }
        stack.push({ f: f, last: last });
      } else if (/^<\/span/i.test(tok)) {
        var e = stack.pop();
        if (e && e.last) open = null;
      }
    }
    var masked = maskSource(src), cursor = 0;
    function snippet(at, len) {
      var a = src.lastIndexOf("\n", at - 1) + 1, b = src.indexOf("\n", at + len);
      if (b < 0) b = src.length;
      var from = Math.max(a, at - 40), to = Math.min(b, at + len + 40);
      return (from > a ? "..." : "") + src.slice(from, to).trim() + (to < b ? "..." : "");
    }
    return findings.map(function (f) {
      var match = f.text.replace(/\s+/g, " ").trim(), rx = null, skip = 0;
      if (f.rule === "dash") rx = /[\u2014\u2013]/g;
      else if (f.rule === "filler") { rx = new RegExp("(^|[^\\p{L}\\p{N}_])(" + reEscape(match).replace(/ /g, "\\s+") + ")(?![\\p{L}\\p{N}_])", "giu"); skip = 1; }
      else if (f.rule === "ticket-id") rx = new RegExp("(^|[^A-Za-z0-9_-])(" + reEscape(match) + ")(?![A-Za-z0-9])", "g"), skip = 1;
      else {
        var words = match.match(/[\p{L}\p{N}]+/gu) || [];
        if (words.length) rx = new RegExp(words.slice(0, 4).map(reEscape).join("[^\\p{L}\\p{N}]+"), "giu");
      }
      var hit = null, line = null;
      if (rx) { rx.lastIndex = cursor; hit = rx.exec(masked); }
      var out = { rule: f.rule, line: null, excerpt: match.length > 100 ? match.slice(0, 100) + "..." : match, message: f.message };
      if (hit) {
        var at = hit.index + (skip ? hit[1].length : 0);
        out.line = masked.slice(0, at).split("\n").length;
        if (f.rule !== "long-sentence") out.excerpt = snippet(at, hit[0].length - (skip ? hit[1].length : 0));
        cursor = at + 1;
      }
      if (f.rule !== "long-sentence") out.match = match;
      return out;
    });
  }

  // ---- render ----
  var source = must(opt.src);
  var settings = {};
  for (var k in (opt.settings || {})) settings[k] = opt.settings[k];
  settings.surface = "cli";
  if (opt.fontMode) settings.theme = opt.fontMode;
  // docx fallback: formulas as plain TeX in a code span, which textutil can carry
  if (opt.mathAs === "tex") {
    katex.renderToString = function (tex, o) {
      return (o && o.displayMode ? "<br><code>" : "<code>") + esc(tex) + (o && o.displayMode ? "</code><br>" : "</code>");
    };
  }

  var notes = footnotes(source);
  var page = SD.render(protectCode(prePasses(notes.src)), settings);
  if (opt.lintOut) {
    var cfg = page.config || {};
    var rulesOn = [["xrayDashes", "dash"], ["xrayLongSentences", "long-sentence"], ["xrayFillers", "filler"], ["xrayTicketIds", "ticket-id"]]
      .filter(function (r) { return cfg[r[0]] && (r[0] !== "xrayFillers" || (cfg.xrayFillerWords || []).length > 0); })
      .map(function (r) { return r[1]; });
    var lint = { rules: rulesOn, sentenceWordLimit: cfg.xraySentenceWords, findings: lintFindings(page.body, source) };
    $(JSON.stringify(lint) + "\n").writeToFileAtomicallyEncodingError(opt.lintOut, true, $.NSUTF8StringEncoding, null);
  }
  var body = page.body;
  body = unguard(body);
  body = wrapCode(body);
  body = frontmatterExtras(body);
  body = calloutBreak(body);
  body = tableAttrs(body);
  body = blankRows(body);
  body = body.replace(/<ul>(\s*<li class="task-list-item">)/g, '<ul class="task-list">$1');
  var ids = headingIds(body);
  body = ids.html + (notes.html ? "\n" + notes.html : "");
  if (opt.embedImages || opt.absImages) body = embedImages(body);
  var hasMath = /class="katex/.test(body);

  if (!opt.standalone) {
    $(body + "\n").writeToFileAtomicallyEncodingError(opt.out, true, $.NSUTF8StringEncoding, null);
    return "";
  }

  // ---- head ----
  function style(css) { return "<style>\n" + css + "\n</style>"; }

  // katex.min.css plus its fonts as woff2 data URIs, only when the page has math. From the app
  // the stylesheet already carries its fonts (scripts/build-ql-katex), so nothing matches here;
  // in a checkout it names fonts/*.woff2 and they come from assets/katex/fonts.
  function katexCss() {
    var css = must(RES + "/katex.min.css");
    return css.replace(/url\(fonts\/([^)]+\.woff2)\) format\("woff2"\)(?:,url\(fonts\/[^)]+\) format\("[a-z0-9]+"\))*/g,
      function (whole, file) {
        var b64 = base64Of(ASSETS + "/katex/fonts/" + file);
        return b64 === null ? whole : 'url(data:font/woff2;base64,' + b64 + ') format("woff2")';
      });
  }

  // Mirror the editor's Markdown preview fonts (port of build_font_override).
  function fontOverride() {
    if (!opt.vscodeSettings) return "";
    var txt = readText(opt.vscodeSettings);
    if (txt === null) return "";
    function re(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }
    function s(key) { var m = new RegExp('"' + re(key) + '"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"').exec(txt); return m ? m[1] : null; }
    function n(key) { var m = new RegExp('"' + re(key) + '"\\s*:\\s*([0-9.]+)').exec(txt); return m ? m[1] : null; }
    var rules = [], ff = s("markdown.preview.fontFamily"), fs = n("markdown.preview.fontSize"),
      lh = n("markdown.preview.lineHeight"), cf = s("editor.fontFamily");
    if (ff) rules.push("  --markdown-font-family: " + ff + ";");
    if (fs) rules.push("  --markdown-font-size: " + fs + "px;");
    if (lh) rules.push("  --markdown-line-height: " + lh + ";");
    if (cf) rules.push("  --vscode-editor-font-family: " + cf + ";");
    if (!rules.length) return "";
    return "<style>\n/* spacedown: fonts mirrored from " + opt.vscodeSettings + " */\n:root {\n" + rules.join("\n") + "\n}\n</style>";
  }

  // The iA fonts as data URIs (port of scripts/ia-fontface-css), for themes that name them.
  function iaFaces() {
    var dir = ROOT + "/assets/fonts/ia";
    if (!FM.fileExistsAtPath(dir)) return "";  // a bundled CLI leaves the fonts out on purpose
    var faces = [
      ["iA Writer Quattro V", "normal", "iAWriterQuattroV.ttf"], ["iA Writer Quattro V", "italic", "iAWriterQuattroV-Italic.ttf"],
      ["iA Writer Mono V", "normal", "iAWriterMonoV.ttf"], ["iA Writer Mono V", "italic", "iAWriterMonoV-Italic.ttf"]];
    var out = ["/* iA Writer fonts (SIL OFL 1.1) embedded by the spacedown CLI. */"];
    for (var i = 0; i < faces.length; i++) {
      var b64 = base64Of(dir + "/" + faces[i][2]);
      if (b64 === null) return "";
      out.push('@font-face { font-family: "' + faces[i][0] + '"; font-style: ' + faces[i][1] +
        '; font-weight: 100 900; src: url(data:font/ttf;base64,' + b64 + ') format("truetype"); }');
    }
    return out.join("\n");
  }

  var READ_CSS = "/* spacedown read mode: proportional serif prose, monospace kept where it carries\n" +
    "   meaning (code, tables). Local fonts only (no web fonts). --font-mode=mono reverts. */\n" +
    "html, body {\n" +
    "  /* Georgia first: full Vietnamese coverage (proper horn diacritics on u and o). Charter\n" +
    "     lacks Vietnamese glyphs; ui-serif is skipped because Chromium does not support it. */\n" +
    '  font-family: Georgia, "Iowan Old Style", "Palatino Linotype", Palatino, "Times New Roman", serif;\n' +
    "  font-size: 15px;\n  line-height: 1.6;\n}\n" +
    "code, kbd, samp, pre, pre code,\ntable, th, td {\n" +
    '  font-family: "JetBrains Mono", ui-monospace, "SF Mono", Menlo, "DejaVu Sans Mono", monospace;\n' +
    "  /* 13px (~87% of the 15px body) matches the serif's optical size; GitHub uses 85%. */\n" +
    "  font-size: 13px;\n}\n" +
    "pre code { font-size: inherit; } /* don't double-shrink code inside pre */\n" +
    ".katex-display > .katex { font-size: 1.04em; } /* display math reads a touch small against serif */\n" +
    "/* Inline math: the base sheet sizes it for the MONO body; Georgia's x-height sits closer\n" +
    "   to KaTeX's, so parity is about 1.10em here. */\n" +
    "body :not(.katex-display) > .katex { font-size: 1.10em; }";

  // What pandoc's default stylesheet gave every page, which the head assets are written on
  // top of. Math has no .math wrapper any more, so inline math is sized by position.
  var baseCss = must(ASSETS + "/cli-base.css");
  var mathCss = "/* inline math (the base sheet sized it for the MONO body, x-height gap) */\n" +
    "body :not(.katex-display) > .katex { font-size: 1.23em; }";

  var head = [];
  head.push('<meta charset="utf-8">');
  head.push('<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes">');
  head.push("<title>" + esc(opt.title) + "</title>");
  head.push(style(baseCss));
  if (hasMath) head.push(style(katexCss()));
  var styleHead = readText(ROOT + "/assets/vscode-preview-head.html");
  if (styleHead !== null) head.push(styleHead);
  else log("style asset not found at " + ROOT + "/assets/vscode-preview-head.html; rendering without the reading look");
  head.push(style(mathCss));
  var hljsCss = readText(RES + "/hljs-theme.css");
  if (hljsCss !== null) head.push(style(hljsCss));
  var dir = srcDir;
  head.push('<base href="' + escAttr($.NSURL.fileURLWithPath(dir).absoluteString.js.replace(/\/?$/, "/")) + '">');
  var fonts = fontOverride();
  if (fonts) head.push(fonts);
  var mode = page.config.theme;
  var themeCss = opt.themeOverride || (/^(ia|tm|paper)$/.test(mode) ? ASSETS + "/" + mode + "-theme.css" : "");
  if (mode === "read") head.push(style(READ_CSS));
  else if (themeCss) {
    var theme = readText(themeCss);
    if (theme === null) log("theme asset not found at " + themeCss + "; --font-mode=" + mode + " has no effect");
    else {
      var faces = "";
      if (opt.embedFonts && theme.indexOf("iA Writer") >= 0) {
        faces = iaFaces();
      }
      head.push(style((faces ? faces + "\n" : "") + theme));
    }
  }
  var chromeHead = readText(ASSETS + "/reading-chrome-head.html"), chromeFoot = readText(ASSETS + "/reading-chrome-foot.html");
  var haveChrome = chromeHead !== null && chromeFoot !== null;
  if (haveChrome) head.push(chromeHead);
  var qlSettings = readText(RES + "/ql-settings.css");
  if (qlSettings !== null && qlSettings.replace(/\/\*[\s\S]*?\*\//g, "").trim()) head.push(style(qlSettings));
  if (page.css) head.push(style(page.css));

  // ---- foot ----
  var foot = [];
  if (haveChrome) {
    var skim = readText(ASSETS + "/skim-surprise.html");
    if (skim !== null) foot.push(skim);
    // The raw markdown, base64 on one line, so copy-source works offline and from file://.
    foot.push('<script type="application/x-sd-source" id="sd-src">' + base64Of(opt.src) + "</script>");
    foot.push(chromeFoot);
  }
  // Page time: the plug-ins' key, init, print and reset hooks (the Finder panel runs none).
  var bootCfg = JSON.stringify(page.config).replace(/</g, "\\u003c");
  foot.push("<script>\n" + pageScripts.join("\n").replace(/<\/script/gi, "<\\/script") +
    "\nSD.boot(document, " + bootCfg + ");\n</script>");
  if (opt.livereload) {
    var lr = readText(ASSETS + "/livereload-foot.html");
    if (lr !== null) foot.push(lr);
  }

  var toc = haveChrome ? tocNav(ids.toc) : "";
  var html = "<!DOCTYPE html>\n<html lang=\"en\" " + page.attrs + ">\n<head>\n" + head.join("\n") + "\n</head>\n<body>\n" +
    (page.chrome ? page.chrome + "\n" : "") + (toc ? toc + "\n" : "") + body + "\n" + foot.join("\n") + "\n</body>\n</html>\n";
  $(html).writeToFileAtomicallyEncodingError(opt.out, true, $.NSUTF8StringEncoding, null);
  return "";
}

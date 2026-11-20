// xray.js: the Writing X-ray lens. Marks, inside prose only, four things a careful writer
// cuts: em and en dashes, sentences over a word limit, filler words, and ticket or spec
// IDs. Loaded after ql-render.js; registers with SD. Hooks and settings: docs/contract-r1.md.
//
// Render time only, so it works in the Finder panel, which runs no scripts:
//   transform  wraps each hit in <span class="sd-xr sd-xr-RULE" title="...">
//   controls   a hidden checkbox #sd-xray (checked when xrayEnabled)
//   toolbar    the label that toggles it, with a legend that shows while it is on
//   css        marks look plain until the checkbox is checked: #sd-xray:checked ~ * .sd-xr-RULE
//              (a long sentence's last piece carries data-sd-words; its ::after is the "27w" tag,
//              so the tag adds no text to the DOM that copy, Skim or BeeLine could see)
// No :has(): the sibling selector above is enough. No regex lookbehind: JavaScriptCore has it
// only from macOS 13.3, and the deployment target is 13.0.
(function (global) {
  "use strict";
  if (!global.SD) return;

  var EM = "\u2014", EN = "\u2013";
  var OPAQUE = "\uE000"; // stands for one skipped inline span (code, math) inside a sentence
  var LETTER = "\\p{L}\\p{N}\\p{M}_";

  // ---- HTML scan ----------------------------------------------------------------------
  // Elements whose text is never marked: code, pre, math, scripts, svg, and KaTeX output.
  var SKIP_TAGS = { pre: 1, code: 1, kbd: 1, samp: 1, script: 1, style: 1, svg: 1, math: 1,
    textarea: 1, title: 1 };
  // A boundary between blocks (or a line break): a sentence never runs across one.
  var BLOCK_TAGS = { p: 1, div: 1, li: 1, ul: 1, ol: 1, dl: 1, dt: 1, dd: 1, blockquote: 1,
    h1: 1, h2: 1, h3: 1, h4: 1, h5: 1, h6: 1, table: 1, thead: 1, tbody: 1, tfoot: 1, tr: 1,
    td: 1, th: 1, caption: 1, hr: 1, br: 1, details: 1, summary: 1, section: 1, article: 1,
    figure: 1, figcaption: 1, header: 1, footer: 1, aside: 1, nav: 1, main: 1 };
  var TOKEN_RE = /<!--[\s\S]*?-->|<[^>]*>|[^<]+|</g;
  var TAG_NAME_RE = /^<(\/?)([A-Za-z][A-Za-z0-9-]*)/;
  var MATH_CLASS_RE = /\bclass\s*=\s*["'][^"']*\bkatex[a-z-]*\b/;

  var ENTITIES = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: "\u00A0",
    mdash: EM, ndash: EN, hellip: "\u2026", rsquo: "\u2019", lsquo: "\u2018",
    rdquo: "\u201D", ldquo: "\u201C" };

  // A text node, decoded for scanning. scan is the plain text; map[i] is the offset in the
  // raw HTML of scan[i], and map[scan.length] is the raw length, so a scan range converts to
  // a raw range without splitting an entity.
  function decode(raw) {
    var scan = "", map = [], pos = 0;
    var re = /&(#x[0-9A-Fa-f]+|#[0-9]+|[A-Za-z][A-Za-z0-9]*);/g, m;
    function add(ch, from) { for (var k = 0; k < ch.length; k++) map.push(from); scan += ch; }
    function plain(from, to) { for (var p = from; p < to; p++) add(raw.charAt(p), p); }
    while ((m = re.exec(raw)) !== null) {
      plain(pos, m.index);
      var name = m[1], ch;
      if (name.charAt(0) === "#") {
        var code = name.charAt(1) === "x" || name.charAt(1) === "X"
          ? parseInt(name.slice(2), 16) : parseInt(name.slice(1), 10);
        try { ch = String.fromCodePoint(code); } catch (e) { ch = "\uFFFD"; }
      } else {
        ch = Object.prototype.hasOwnProperty.call(ENTITIES, name) ? ENTITIES[name] : "\uFFFC";
      }
      add(ch, m.index);
      pos = m.index + m[0].length;
    }
    plain(pos, raw.length);
    map.push(raw.length);
    return { raw: raw, scan: scan, map: map, marks: [], clips: [] };
  }

  // Split html into parts: tags, and text nodes (decoded) outside any skipped element. Parts
  // carry the run they belong to; a run is the text between two block boundaries, with every
  // skipped span inside it standing for one OPAQUE word.
  function scanHtml(html) {
    var parts = [], runs = [], run = { text: "", nodes: [] };
    var skipTag = null, skipDepth = 0;
    var m;
    function closeRun() {
      if (run.nodes.length) runs.push(run);
      run = { text: "", nodes: [] };
    }
    TOKEN_RE.lastIndex = 0;
    while ((m = TOKEN_RE.exec(html)) !== null) {
      var tok = m[0];
      var tag = tok.charAt(0) === "<" && tok.charAt(1) !== "!" ? TAG_NAME_RE.exec(tok) : null;
      if (tag) {
        var closing = tag[1] === "/", name = tag[2].toLowerCase();
        var selfClosed = /\/>$/.test(tok);
        if (skipTag !== null) {
          if (name === skipTag && !selfClosed) skipDepth += closing ? -1 : 1;
          if (skipDepth === 0) skipTag = null;
        } else if (!closing && !selfClosed &&
            (SKIP_TAGS[name] === 1 || (name === "span" && MATH_CLASS_RE.test(tok)))) {
          skipTag = name; skipDepth = 1;
          run.text += OPAQUE;
        } else if (BLOCK_TAGS[name] === 1) {
          closeRun();
        }
        parts.push(tok);
      } else if (tok.charAt(0) === "<" && tok.length > 1) {
        parts.push(tok); // a comment
      } else if (skipTag !== null || tok === "<") {
        parts.push(tok);
      } else {
        var node = decode(tok);
        node.runStart = run.text.length;
        run.text += node.scan;
        run.nodes.push(node);
        parts.push(node);
      }
    }
    closeRun();
    return { parts: parts, runs: runs };
  }

  // ---- Rules ---------------------------------------------------------------------------

  var cache = { key: "", re: null };
  function fillerRegex(words) {
    var key = words.join("\u0000");
    if (cache.key === key && cache.re) return cache.re;
    var alts = words.slice().sort(function (a, b) { return b.length - a.length; })
      .map(function (w) {
        return w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replace(/\s+/g, "\\s+");
      });
    var re = alts.length ? new RegExp("(^|[^" + LETTER + "])(" + alts.join("|") +
      ")(?![" + LETTER + "])", "giu") : null;
    cache = { key: key, re: re };
    return re;
  }

  // Ticket and spec IDs: two to ten capitals, a hyphen, digits. Standards that look the same
  // (UTF-8, SHA-256) are not tickets.
  var TICKET_RE = /(^|[^A-Za-z0-9_-])([A-Z][A-Z0-9]{1,9}-\d{1,6})(?![A-Za-z0-9])(?!\.\d)/g;
  var NOT_TICKET = { UTF: 1, ISO: 1, SHA: 1, MD: 1, AES: 1, RSA: 1, GPT: 1, COVID: 1, SARS: 1,
    TLS: 1, SSL: 1, WPA: 1, USB: 1, HTTP: 1, IPV: 1, IEEE: 1, RFC: 1, ECMA: 1, CP: 1,
    PDF: 1, MP: 1, H: 1 };
  var DASH_RE = /[\u2014\u2013]/g;

  function addMark(node, from, to, cls, title) {
    node.marks.push({ s: from, e: to, cls: cls, title: title });
  }

  function markNode(node, cfg, fillerRe) {
    var s = node.scan, m;
    if (cfg.xrayDashes && (s.indexOf(EM) >= 0 || s.indexOf(EN) >= 0)) {
      DASH_RE.lastIndex = 0;
      while ((m = DASH_RE.exec(s)) !== null) {
        addMark(node, m.index, m.index + 1, "dash",
          (m[0] === EM ? "em dash" : "en dash") + ": try a comma, colon or full stop");
      }
    }
    if (fillerRe) {
      fillerRe.lastIndex = 0;
      while ((m = fillerRe.exec(s)) !== null) {
        var at = m.index + m[1].length;
        addMark(node, at, at + m[2].length, "filler", "filler word: " + m[2].toLowerCase());
        if (m[2] === "") fillerRe.lastIndex++;
      }
    }
    if (cfg.xrayTicketIds && s.indexOf("-") >= 0) {
      TICKET_RE.lastIndex = 0;
      while ((m = TICKET_RE.exec(s)) !== null) {
        var prefix = m[2].slice(0, m[2].indexOf("-"));
        if (NOT_TICKET[prefix] === 1) continue;
        var from = m.index + m[1].length;
        addMark(node, from, from + m[2].length, "ticket", "ticket or spec ID: " + m[2]);
      }
    }
  }

  var ABBREVIATIONS = { dr: 1, mr: 1, mrs: 1, ms: 1, prof: 1, sr: 1, jr: 1, st: 1, vs: 1,
    etc: 1, no: 1, fig: 1, eg: 1, ie: 1, approx: 1, inc: 1, ltd: 1, co: 1, tp: 1, ths: 1 };
  var STOP_RE = /[.!?\u2026]+["'\u201D\u2019)\]]*(?=\s|$)/g;
  var WORD_RE = new RegExp("\\p{N}+(?:[.,]\\p{N}+)+|[" + LETTER.replace("_", "") + OPAQUE +
    "]+(?:['\u2019\\-][" + LETTER.replace("_", "") + "]+)*", "gu");
  var LOWER_RE = /^\p{Ll}/u;

  function countWords(text) {
    var m = text.match(WORD_RE);
    return m ? m.length : 0;
  }

  // Sentence ranges of one run as [start, end) offsets into run.text, spaces trimmed. A
  // stop followed by a lowercase letter, or after an abbreviation or a single letter
  // (e.g., U.S., Dr.), does not end a sentence.
  function sentences(text) {
    var out = [], start = 0, m;
    function push(end) {
      var a = start, b = end;
      while (a < b && /\s/.test(text.charAt(a))) a++;
      while (b > a && /\s/.test(text.charAt(b - 1))) b--;
      if (b > a) out.push([a, b]);
    }
    STOP_RE.lastIndex = 0;
    while ((m = STOP_RE.exec(text)) !== null) {
      var end = m.index + m[0].length;
      var before = /([\p{L}\p{N}\p{M}]+)$/u.exec(text.slice(Math.max(0, m.index - 12), m.index));
      var word = before ? before[1].toLowerCase() : "";
      if (word.length === 1 && /\p{L}/u.test(word) || ABBREVIATIONS[word] === 1) continue;
      var rest = text.slice(end).replace(/^\s+/, "");
      if (rest !== "" && LOWER_RE.test(rest)) continue;
      push(end);
      start = end;
    }
    push(text.length);
    return out;
  }

  function markLong(run, limit) {
    sentences(run.text).forEach(function (sp) {
      var words = countWords(run.text.slice(sp[0], sp[1]));
      if (words <= limit) return;
      var title = "long sentence: " + words + " words, limit " + limit;
      var last = null;
      run.nodes.forEach(function (node) {
        var a = Math.max(sp[0], node.runStart) - node.runStart;
        var b = Math.min(sp[1], node.runStart + node.scan.length) - node.runStart;
        if (b <= a || /^\s*$/.test(node.scan.slice(a, b))) return;
        last = { s: a, e: b, title: title };
        node.clips.push(last);
      });
      if (last) last.words = words; // the word-count tag goes after the sentence's last piece
    });
  }

  // ---- Output --------------------------------------------------------------------------

  function esc(s) { return s.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;"); }

  function span(cls, title, inner, words) {
    return '<span class="sd-xr ' + cls + '" title="' + esc("X-ray, " + title) + '"' +
      (words ? ' data-sd-words="' + words + '"' : "") + ">" + inner + "</span>";
  }

  // Raw HTML of one text node with its marks. Marks cannot overlap (the first wins), and a
  // mark that straddles a long-sentence edge is dropped so the spans nest.
  function renderNode(node) {
    if (!node.marks.length && !node.clips.length) return node.raw;
    var map = node.map, raw = node.raw;
    var marks = node.marks.slice().sort(function (a, b) { return a.s - b.s || b.e - a.e; });
    var kept = [], edge = 0;
    marks.forEach(function (mk) {
      if (mk.s < edge) return;
      for (var i = 0; i < node.clips.length; i++) {
        var c = node.clips[i];
        if ((mk.s < c.s && mk.e > c.s) || (mk.s < c.e && mk.e > c.e)) return;
      }
      kept.push(mk); edge = mk.e;
    });
    var clips = node.clips.slice().sort(function (a, b) { return a.s - b.s; });
    var out = "", at = 0, ki = 0;
    function plainTo(limit) { // raw text from scan offset `at` up to `limit`, with marks inside
      while (ki < kept.length && kept[ki].s < limit) {
        var mk = kept[ki++];
        out += raw.slice(map[at], map[mk.s]);
        out += span("sd-xr-" + mk.cls, mk.title, raw.slice(map[mk.s], map[mk.e]));
        at = mk.e;
      }
      out += raw.slice(map[at], map[limit]);
      at = limit;
    }
    clips.forEach(function (c) {
      plainTo(c.s);
      var save = out;
      out = "";
      plainTo(c.e);
      out = save + span("sd-xr-long", c.title, out, c.words);
    });
    plainTo(node.scan.length);
    return out;
  }

  function transform(html, cfg) {
    var wantFiller = cfg.xrayFillers && cfg.xrayFillerWords.length > 0;
    if (!cfg.xrayDashes && !cfg.xrayLongSentences && !wantFiller && !cfg.xrayTicketIds) return html;
    var tree = scanHtml(html);
    var fillerRe = wantFiller ? fillerRegex(cfg.xrayFillerWords) : null;
    tree.runs.forEach(function (run) {
      run.nodes.forEach(function (node) { markNode(node, cfg, fillerRe); });
      if (cfg.xrayLongSentences) markLong(run, cfg.xraySentenceWords);
    });
    var out = "";
    tree.parts.forEach(function (p) { out += typeof p === "string" ? p : renderNode(p); });
    return out;
  }

  // ---- Chrome and style ----------------------------------------------------------------

  var RULES = [
    { key: "xrayDashes", cls: "dash", label: "dash", note: "em and en dashes" },
    { key: "xrayLongSentences", cls: "long", label: "long sentence", note: "sentences over the word limit" },
    { key: "xrayFillers", cls: "filler", label: "filler", note: "filler words" },
    { key: "xrayTicketIds", cls: "ticket", label: "ticket ID", note: "ticket and spec IDs" }
  ];

  function activeRules(cfg) {
    return RULES.filter(function (r) {
      return cfg[r.key] && (r.key !== "xrayFillers" || cfg.xrayFillerWords.length > 0);
    });
  }

  function controls(cfg) {
    return '<input type="checkbox" id="sd-xray" hidden' + (cfg.xrayEnabled ? " checked" : "") + ">";
  }

  function toolbar(cfg) {
    var rules = activeRules(cfg);
    var title = rules.length
      ? "Writing X-ray: marks " + rules.map(function (r) {
          return r.cls === "long" ? r.note.replace("the word limit", cfg.xraySentenceWords + " words") : r.note;
        }).join(", ")
      : "Writing X-ray: every rule is off in Settings";
    var legend = rules.map(function (r) {
      return '<span class="sd-xr-chip sd-xr-chip-' + r.cls + '">' + r.label + "</span>";
    }).join("");
    return '<label class="sd-xr-toggle" for="sd-xray" title="' + esc(title) + '">' +
      '<span class="sd-xr-name">X-ray</span>' +
      (legend ? '<span class="sd-xr-legend">' + legend + "</span>" : "") + "</label>";
  }

  // Marks carry their own ink so contrast holds in every theme. Light fills differ in
  // lightness (orange darkest, yellow lightest) and each rule has its own line style, so the
  // four are told apart without color. Dark fills are deep tints under light ink. A long
  // sentence is not filled (a whole sentence of fill is too loud): it gets a dotted underline
  // in --sd-xr-longline and a word-count tag on the long fill.
  var LIGHT = "--sd-xr-ink:#1a1a1a;--sd-xr-dash:#db8f58;--sd-xr-long:#92bde8;" +
    "--sd-xr-ticket:#8fe687;--sd-xr-filler:#f7ea7a;--sd-xr-longline:#2557c7;";
  var DARK = "--sd-xr-ink:#f2f2f2;--sd-xr-dash:#422510;--sd-xr-long:#193f66;" +
    "--sd-xr-ticket:#1d5c17;--sd-xr-filler:#71631c;--sd-xr-longline:#8ab4f8;";
  var ON = "#sd-xray:checked ~ * .sd-xr-";

  function css(cfg) {
    var marks = [
      [ON + "dash", "background:var(--sd-xr-dash)"],
      [ON + "long", "color:inherit;padding:0;text-decoration:underline dotted var(--sd-xr-longline);" +
        "-webkit-text-decoration:underline dotted var(--sd-xr-longline);text-decoration-thickness:2px;text-underline-offset:.3em"],
      [ON + "ticket", "background:var(--sd-xr-ticket);box-shadow:inset 0 0 0 1px var(--sd-xr-ink)"],
      [ON + "filler", "background:var(--sd-xr-filler);text-decoration:underline wavy;text-decoration-thickness:1px"]
    ].map(function (r) { return r[0] + "{" + r[1] + "}"; }).join("\n");
    var chips = ["dash", "long", "ticket", "filler"].map(function (c) {
      return ".sd-xr-chip-" + c + "{background:var(--sd-xr-" + c + ")}";
    }).join("\n");
    return [
      ":root{" + LIGHT + "}",
      "@media (prefers-color-scheme:dark){:root:not([data-sd-appearance=\"light\"]){" + DARK + "}}",
      ":root[data-sd-appearance=\"dark\"]{" + DARK + "}",
      ".sd-xr{pointer-events:none}",
      "#sd-xray:checked ~ * .sd-xr{pointer-events:auto;color:var(--sd-xr-ink);border-radius:2px;" +
        "padding:0 .06em;-webkit-box-decoration-break:clone;box-decoration-break:clone}",
      marks,
      ON + "long[data-sd-words]::after{content:attr(data-sd-words) \"w\";display:inline-block;margin-left:6px;padding:1px 5px;border-radius:4px;" +
        "background:var(--sd-xr-long);color:var(--sd-xr-ink);font:400 11px/1.3 ui-monospace,SFMono-Regular,Menlo,monospace;" +
        "vertical-align:2px;text-decoration:none;white-space:nowrap}",
      ".sd-xr-toggle{display:flex;align-items:center;gap:8px;cursor:pointer;padding:3px 9px;" +
        "border:1px solid var(--ql-rule,#1a1a1a);border-radius:4px;background:var(--ql-paper,#fcfcfc);" +
        "color:var(--ql-ink,#1a1a1a);user-select:none;-webkit-user-select:none}",
      "#sd-xray:checked ~ .sd-ql-toolbar .sd-xr-name{font-weight:600}",
      ".sd-xr-legend{display:none;gap:4px}",
      "#sd-xray:checked ~ .sd-ql-toolbar .sd-xr-legend{display:flex}",
      ".sd-xr-chip{padding:0 6px;border-radius:2px;color:var(--sd-xr-ink);font-size:11px}",
      chips,
      ".sd-xr-chip-ticket{box-shadow:inset 0 0 0 1px var(--sd-xr-ink)}"
    ].join("\n");
  }

  global.SD.register({
    id: "xray",
    order: 100,
    transform: transform,
    css: css,
    controls: controls,
    toolbar: toolbar
  });
})(typeof globalThis !== "undefined" ? globalThis : this);

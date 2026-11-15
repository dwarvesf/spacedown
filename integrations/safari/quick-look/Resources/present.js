// present.js: Present mode. The document is cut into slides, one per H2 and one per
// thematic break (---); the H1 and anything before the first cut is the title slide.
// Loaded after ql-render.js and xray.js; registers with SD. Hooks: docs/contract-r1.md.
//
// Two layers, because the Finder panel runs no JavaScript:
//   1. Render time (transform, controls, toolbar, css), works everywhere. A hidden
//      checkbox #sd-present is the switch; a "Present" label in the toolbar flips it; CSS
//      turns the checked state into full-height slides with scroll snapping, so the arrow
//      and Page Down keys move slide by slide with no script. Unchecked, the page reads as
//      before: the slides are plain wrappers with no style.
//   2. Page time (init, key, print, reset), only under SD.boot in a page that runs
//      scripts: P toggles, arrows and Page Up/Down move, Home/End jump, Esc exits, and a
//      "3 / 7" counter follows the slide on screen.
(function (global) {
  "use strict";
  if (!global.SD) return;

  var BOX_ID = "sd-present";
  var SLIDE_CLASS = "sd-slide";

  // Elements that can hold a heading or a rule. A split inside one of them is not a
  // slide boundary. Inline and optionally-closed tags (p, span, a) are not tracked, so a
  // stray unclosed one in raw HTML cannot hide every later split.
  var CONTAINERS = {};
  ("div section article aside blockquote details ul ol li table figure header footer " +
    "main nav form dl fieldset pre").split(" ").forEach(function (n) { CONTAINERS[n] = true; });
  var RAW_TEXT = { script: true, style: true, textarea: true };

  // Offsets where a new slide starts: before each top-level H2, after each top-level HR.
  function cutPoints(html) {
    var re = /<!--[\s\S]*?-->|<(\/?)([A-Za-z][A-Za-z0-9-]*)((?:"[^"]*"|'[^']*'|[^'">])*)>/g;
    var cuts = [], depth = 0, m;
    while ((m = re.exec(html))) {
      if (m[2] === undefined) continue; // a comment
      var name = m[2].toLowerCase(), closing = m[1] === "/";
      if (!closing && RAW_TEXT[name]) {
        var close = new RegExp("</" + name + "\\b", "ig");
        close.lastIndex = re.lastIndex;
        var hit = close.exec(html);
        re.lastIndex = hit ? hit.index : html.length;
        continue;
      }
      if (CONTAINERS[name]) {
        if (closing) depth = Math.max(0, depth - 1);
        else if (!/\/\s*$/.test(m[3])) depth++;
        continue;
      }
      if (depth > 0 || closing) continue;
      if (name === "h2") cuts.push(m.index);
      else if (name === "hr") cuts.push(m.index + m[0].length);
    }
    return cuts;
  }

  // A piece with nothing to show: only whitespace and rules.
  function isBlank(piece) {
    return piece.replace(/<hr\b[^>]*>/gi, "").replace(/\s+/g, "") === "";
  }

  // Slide HTML strings, in order, and whether the first is a title slide. Joining the
  // pieces gives back the input exactly; empty pieces fold into a neighbour.
  function splitSlides(html) {
    var cuts = cutPoints(html).filter(function (c, i, all) {
      return c > 0 && c < html.length && all.indexOf(c) === i;
    }).sort(function (a, b) { return a - b; });
    var pieces = [], prev = 0;
    cuts.forEach(function (c) { pieces.push(html.slice(prev, c)); prev = c; });
    pieces.push(html.slice(prev));
    var slides = [], carry = "";
    pieces.forEach(function (piece) {
      if (isBlank(piece)) {
        if (slides.length) slides[slides.length - 1] += piece; else carry += piece;
      } else {
        slides.push(carry + piece);
        carry = "";
      }
    });
    if (!slides.length) return { slides: [], title: false };
    return { slides: slides, title: !isBlank(pieces[0]) && /<h1\b/i.test(slides[0]) };
  }

  function wrap(html) {
    var parts = splitSlides(html);
    if (!parts.slides.length) return html;
    return parts.slides.map(function (s, i) {
      var cls = SLIDE_CLASS + (i === 0 && parts.title ? " sd-title" : "");
      return '<section class="' + cls + '" data-slide="' + (i + 1) + '">' + s + "</section>";
    }).join("");
  }

  // ---- render time ----

  var CSS =
    // Snap points exist only while a slide has scroll-snap-align (checked, below), so this
    // rule changes nothing on the reading page. It sits on html because :has() is not
    // available on the deployment target.
    "html{scroll-snap-type:y mandatory}" +
    ".sd-present-btn{display:inline-flex;align-items:center;gap:6px;padding:3px 9px;" +
    "border-radius:6px;cursor:pointer;user-select:none;-webkit-user-select:none;" +
    "background:rgba(128,128,128,.16);color:inherit}" +
    ".sd-present-btn:hover{background:rgba(128,128,128,.28)}" +
    ".sd-present-btn .sd-present-off{display:none}" +
    "#sd-present:checked ~ .sd-ql-toolbar .sd-present-btn{background:rgba(128,128,128,.4)}" +
    "#sd-present:checked ~ .sd-ql-toolbar .sd-present-on{display:none}" +
    "#sd-present:checked ~ .sd-ql-toolbar .sd-present-off{display:inline}" +
    ".sd-present-count{display:none;padding:3px 6px;font-variant-numeric:tabular-nums;opacity:.7}" +
    "#sd-present:checked ~ .sd-ql-toolbar .sd-present-count:not(:empty){display:inline-block}" +
    "@media screen{" +
    "#sd-present:checked ~ .sd-slide{box-sizing:border-box;width:100vw;" +
    "margin-left:calc(50% - 50vw);min-height:100vh;padding:7vh 10vw;display:flex;" +
    "flex-direction:column;justify-content:center;font-size:calc(var(--ql-size,18px)*1.6);" +
    "scroll-snap-align:start;scroll-snap-stop:always;overflow-wrap:anywhere}" +
    "#sd-present:checked ~ .sd-slide:first-of-type{margin-top:-2.2rem}" +
    "#sd-present:checked ~ .sd-slide:last-of-type{margin-bottom:-4rem}" +
    "#sd-present:checked ~ .sd-slide hr{display:none}" +
    "#sd-present:checked ~ .sd-slide h1{font-size:1.7em}" +
    "#sd-present:checked ~ .sd-slide h2{font-size:1.4em}" +
    "#sd-present:checked ~ .sd-slide pre,#sd-present:checked ~ .sd-slide table{max-width:100%;overflow:auto}" +
    "#sd-present:checked ~ .sd-title{text-align:center;align-items:center}" +
    "#sd-present:checked ~ .sd-title h1{font-size:2.1em}" +
    "}";

  // ---- page time ----

  function slidesOf(doc) {
    return Array.prototype.slice.call(doc.querySelectorAll("." + SLIDE_CLASS));
  }

  // The switch. A page that took only the body, with no controls, gets one on first use.
  function boxOf(doc, create) {
    var box = doc.getElementById(BOX_ID);
    if (box || !create || !doc.createElement || !doc.body) return box || null;
    box = doc.createElement("input");
    box.setAttribute("type", "checkbox");
    box.setAttribute("id", BOX_ID);
    box.setAttribute("hidden", "");
    box.id = BOX_ID;
    doc.body.insertBefore(box, doc.body.firstChild || null);
    return box;
  }

  function topOf(el) { return el.getBoundingClientRect().top; }

  // Index of the slide nearest the top of the screen.
  function nearest(slides) {
    var best = 0, bestDist = Infinity;
    slides.forEach(function (s, i) {
      var d = Math.abs(topOf(s));
      if (d < bestDist) { best = i; bestDist = d; }
    });
    return best;
  }

  // Index of the slide holding the reading position (last slide that has started).
  function reading(slides) {
    var at = 0;
    slides.forEach(function (s, i) { if (topOf(s) <= 1) at = i; });
    return at;
  }

  function showCount(doc, text) {
    var el = doc.querySelector(".sd-present-count");
    if (el) el.textContent = text;
  }

  function sync(doc) {
    var box = doc.getElementById(BOX_ID), slides = slidesOf(doc);
    if (!box || !box.checked || !slides.length) { showCount(doc, ""); return; }
    showCount(doc, (nearest(slides) + 1) + " / " + slides.length);
  }

  function go(doc, slides, i) {
    var at = Math.max(0, Math.min(slides.length - 1, i));
    slides[at].scrollIntoView({ block: "start" });
    showCount(doc, (at + 1) + " / " + slides.length);
  }

  function toggle(doc) {
    var slides = slidesOf(doc);
    if (!slides.length) return false;
    var box = boxOf(doc, true);
    if (!box) return false;
    var at = reading(slides); // remember the place before the layout changes
    box.checked = !box.checked;
    go(doc, slides, at);
    if (!box.checked) showCount(doc, "");
    return true;
  }

  function leave(doc) {
    var box = doc.getElementById(BOX_ID);
    if (box) box.checked = false;
    showCount(doc, "");
  }

  // The page SD.boot started on; key(ev, cfg) is not handed the document.
  var booted = null;

  var MOVES = {
    ArrowRight: 1, ArrowDown: 1, PageDown: 1,
    ArrowLeft: -1, ArrowUp: -1, PageUp: -1
  };

  global.SD.register({
    id: "present",
    order: 200,

    transform: function (html, cfg) { return wrap(html); },

    controls: function (cfg) {
      return '<input type="checkbox" id="' + BOX_ID + '" hidden>';
    },

    toolbar: function (cfg) {
      return '<label class="sd-present-btn" for="' + BOX_ID + '" title="Present (P)">' +
        '<span class="sd-present-on">Present</span><span class="sd-present-off">Exit</span></label>' +
        '<span class="sd-present-count" aria-live="polite"></span>';
    },

    css: function (cfg) { return CSS; },

    init: function (doc, cfg) {
      booted = doc;
      var win = doc.defaultView;
      if (win && win.addEventListener) {
        win.addEventListener("scroll", function () { sync(doc); });
      }
    },

    key: function (ev, cfg) {
      var doc = ev.target && ev.target.ownerDocument || booted;
      if (!doc || !doc.getElementById) return false;
      var box = doc.getElementById(BOX_ID);
      if (ev.key === "p" || ev.key === "P") return toggle(doc);
      if (!box || !box.checked) return false;
      var slides = slidesOf(doc);
      if (!slides.length) return false;
      if (ev.key === "Escape") { leave(doc); return true; }
      if (ev.key === "Home") { go(doc, slides, 0); return true; }
      if (ev.key === "End") { go(doc, slides, slides.length - 1); return true; }
      if (MOVES[ev.key]) { go(doc, slides, nearest(slides) + MOVES[ev.key]); return true; }
      return false;
    },

    print: function (doc, cfg) { leave(doc); },

    reset: function (doc, cfg) { leave(doc); }
  });
})(typeof globalThis !== "undefined" ? globalThis : this);

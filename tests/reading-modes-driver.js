/* Test driver for the reading modes. tests/smoke.sh inlines this into a rendered page, opens the
   page in a headless browser and reads the JSON from #sd-test-result. It drives the real UI path:
   the Read menu buttons and the keyboard, never the internals. */
(function () {
  "use strict";
  var doc = document.documentElement, R = {};

  function count(sel) { return document.querySelectorAll(sel).length; }
  function color(el) { return getComputedStyle(el).color; }
  function rgb(c) {
    var m = /^rgba?\(([\d.]+)[, ]+([\d.]+)[, ]+([\d.]+)/.exec(c) || /^color\(srgb ([\d.]+) ([\d.]+) ([\d.]+)/.exec(c);
    if (!m) return null;
    var k = c.indexOf("color(") === 0 ? 255 : 1;
    return [m[1] * k, m[2] * k, m[3] * k];
  }
  function dist(a, b) {
    var x = rgb(a), y = rgb(b);
    return x && y ? Math.max(Math.abs(x[0] - y[0]), Math.abs(x[1] - y[1]), Math.abs(x[2] - y[2])) : 999;
  }
  // the colours of a BeeLine word's gradient, left edge first: [[r,g,b], ...] or null when it has none
  function gradient(el) {
    var bg = getComputedStyle(el).backgroundImage;
    if (bg.indexOf("linear-gradient") !== 0) return null;
    var out = [], re = /rgba?\(([^)]*)\)|color\(srgb ([^)]*)\)/g, m;
    while ((m = re.exec(bg))) {
      var parts = (m[1] || m[2]).split(/[ ,\/]+/).filter(Boolean).map(Number), k = m[1] ? 1 : 255;
      out.push([parts[0] * k, parts[1] * k, parts[2] * k]);
    }
    return out.length >= 2 ? out : null;
  }
  function gdist(a, b) { return Math.max(Math.abs(a[0] - b[0]), Math.abs(a[1] - b[1]), Math.abs(a[2] - b[2])); }
  function gLeft(el) { var g = gradient(el); return g ? g[0] : null; }
  function gRight(el) { var g = gradient(el); return g ? g[g.length - 1] : null; }
  // text of every prose element plus how many text nodes it holds: equal before and after means restored
  function sig() {
    var out = [], nodes = 0;
    Array.prototype.forEach.call(document.querySelectorAll("p, li, td, th, blockquote, h1, h2, h3"), function (e) {
      out.push(e.innerHTML);
      var w = document.createTreeWalker(e, NodeFilter.SHOW_TEXT);
      while (w.nextNode()) nodes++;
    });
    return out.join("\n") + "\n#" + nodes;
  }
  function trigger() { return document.querySelector(".sd-read"); }
  function pick(label) {
    trigger().click();
    var items = document.querySelectorAll(".sd-read-item");
    for (var i = 0; i < items.length; i++) {
      if (items[i].textContent === label) { items[i].click(); return true; }
    }
    return false;
  }
  function key(k) {
    window.dispatchEvent(new KeyboardEvent("keydown", { key: k, bubbles: true, cancelable: true }));
  }
  function leftovers() {
    return {
      skim: count(".sd-sk"),
      bionic: count("b.sd-bi"),
      beeline: count(".sd-bl-w, .sd-bl-g, [style*='--bl-']"),
      rsvp: count(".sd-rsvp-overlay")
    };
  }
  function modeClasses() {
    return ["skim", "bionic", "beeline", "rsvp"].filter(function (m) { return doc.classList.contains("sd-" + m); });
  }
  function store(k) { try { return localStorage.getItem(k); } catch (e) { return "no-storage"; } }
  function rsvpWord() {
    var ov = document.querySelector(".sd-rsvp-overlay");
    return ov ? ["l", "o", "r"].map(function (c) { return ov.querySelector(".sd-rsvp-" + c).textContent; }) : null;
  }

  function run() {
    // colours are read right after a switch, so the skim fade must not be mid-transition
    var calm = document.createElement("style");
    calm.textContent = "* { transition: none !important; }";
    document.head.appendChild(calm);
    var t = trigger();
    R.sdSurprise = !!window.sdSurprise;
    R.labels = Array.prototype.map.call(document.querySelectorAll(".sd-read-item"), function (i) { return i.textContent; });
    R.trigger = { popup: t.getAttribute("aria-haspopup"), expanded: t.getAttribute("aria-expanded"), label: t.getAttribute("aria-label"),
      controls: t.getAttribute("aria-controls"), menuHidden: document.getElementById("sd-read-pop").hidden };
    R.noSkimButton = count("button.sd-skim") === 0;
    // what the page did on its own at load: a seeded localStorage may have opened Skim already
    R.boot = { mode: doc.getAttribute("data-sd-read-mode"), scored: doc.hasAttribute("data-sd-skim"), emph: doc.getAttribute("data-sd-skim"),
      spans: count(".sd-sk"), label: t.getAttribute("aria-label"), stored: store("sd-read-mode"), last: store("sd-read-last") };
    if (R.boot.mode) { pick("Off"); R.boot.left = leftovers(); }
    R.base = sig();

    // keyboard: ArrowDown opens and focuses an item, Escape closes and returns focus
    t.focus();
    t.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true, cancelable: true }));
    R.kbOpen = t.getAttribute("aria-expanded") === "true" && document.activeElement.classList.contains("sd-read-item");
    document.activeElement.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true, cancelable: true }));
    R.kbMoved = document.activeElement.getAttribute("role") === "menuitemradio" && document.activeElement.textContent !== "Off";
    document.activeElement.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }));
    R.kbClose = t.getAttribute("aria-expanded") === "false" && document.activeElement === t && document.getElementById("sd-read-pop").hidden;

    // skim: the one scored mode behind the first menu item
    pick("Skim");
    var lv = {};
    ["-2", "-1", "1", "2"].forEach(function (l) { lv[l] = count(".sd-sk[data-sk='" + l + "']"); });
    var scoredSpans = lv["-2"] + lv["-1"] + lv["1"] + lv["2"];
    var text = Array.prototype.map.call(document.querySelectorAll("p, li, td, blockquote"), function (e) { return e.textContent; }).join("\n");
    var res = window.sdSurprise ? window.sdSurprise.analyze(text, { minTokens: 80, intensity: 50 }) : null;
    function levelStyle(l) { var e = document.querySelector(".sd-sk[data-sk='" + l + "']"); return e ? getComputedStyle(e) : null; }
    var m2 = levelStyle("-2"), m1 = levelStyle("-1"), p1 = levelStyle("1"), p2 = levelStyle("2");
    R.skim = { classes: modeClasses(), attr: doc.getAttribute("data-sd-read-mode"), checked: document.querySelector(".sd-read-item[aria-checked='true']").textContent,
      scored: doc.hasAttribute("data-sd-skim"), emph: doc.getAttribute("data-sd-skim"), spans: scoredSpans, levels: lv, stored: store("sd-read-mode"),
      lang: res && !res.skipped ? res.stats.lang : null, skipped: res && res.skipped ? res.reason : null,
      style: { dimMild: m1 && m1.opacity, dimStrong: m2 && m2.opacity, plain: p1 && p1.opacity, weight1: p1 && p1.fontWeight, weight2: p2 && p2.fontWeight,
        heatMild: p1 && p1.backgroundColor, heatStrong: p2 && p2.backgroundColor, underline: p2 && p2.textDecorationLine },
      inSkipped: count("pre .sd-sk, code .sd-sk, a .sd-sk, strong .sd-sk, h1 .sd-sk, th .sd-sk, table.sd-frontmatter .sd-sk"),
      label: t.getAttribute("aria-label"), left: leftovers() };
    // a second pass on top must not stack: picking the mode again, or switching away and back, gives the same count
    pick("Skim");
    R.skim.idempotent = count(".sd-sk") === scoredSpans;

    // S toggles the last mode off and on
    key("s"); var afterOff = doc.getAttribute("data-sd-read-mode");
    key("S"); var afterOn = doc.getAttribute("data-sd-read-mode");
    R.sKey = { off: afterOff, on: afterOn };

    // bionic
    pick("Bionic");
    var bolds = Array.prototype.map.call(document.querySelectorAll("b.sd-bi"), function (b) { return b.textContent; });
    R.bionic = { classes: modeClasses(), count: bolds.length, sample: bolds.slice(0, 400).join("|"),
      inSkipped: count("pre b.sd-bi, code b.sd-bi, a b.sd-bi, strong b.sd-bi, h1 b.sd-bi, th b.sd-bi"),
      weight: bolds.length ? getComputedStyle(document.querySelector("b.sd-bi")).fontWeight : null,
      stored: store("sd-read-mode"), left: leftovers() };
    key("s"); R.bionic.sOffRestores = sig() === R.base;
    key("s");

    // beeline: the last paragraph wraps onto several lines
    pick("BeeLine");
    var paras = document.querySelectorAll("p"), longP = null;
    Array.prototype.forEach.call(paras, function (p) { if (p.querySelectorAll(".sd-bl-w").length > 30) longP = p; });
    var lines = [];
    if (longP) {
      Array.prototype.forEach.call(longP.querySelectorAll(".sd-bl-w"), function (w) {
        var top = w.offsetTop, line = lines[lines.length - 1];
        if (!line || Math.abs(top - line.top) > 4) lines.push(line = { top: top, words: [] });
        line.words.push(w);
      });
    }
    // each word paints its own slice of the line gradient: left and right colours, joined word to word
    var join = 0, startInk = null, endBlue = null, seam = 0, seamPairs = 0, withGradient = 0, clipped = 0, clear = 0, flat = 0, wide = 0, midInk = false;
    var allWords = longP ? Array.prototype.slice.call(longP.querySelectorAll(".sd-bl-w")) : [];
    allWords.forEach(function (w) {
      var cs = getComputedStyle(w);
      if (gradient(w)) withGradient++;
      if (cs.webkitBackgroundClip === "text" || cs.backgroundClip === "text") clipped++;
      if (cs.webkitTextFillColor === "rgba(0, 0, 0, 0)") clear++;
    });
    if (lines.length > 2) {
      var ink = color(longP), inkRgb = rgb(ink);
      startInk = gdist(gLeft(lines[0].words[0]), inkRgb);
      endBlue = gRight(lines[0].words[lines[0].words.length - 1]);
      for (var i = 0; i + 1 < lines.length; i++) {
        var a = lines[i].words[lines[i].words.length - 1], b = lines[i + 1].words[0];
        join = Math.max(join, gdist(gRight(a), gLeft(b)));
      }
      lines.forEach(function (line) {
        for (var j = 0; j + 1 < line.words.length; j++) {
          var gap = line.words[j + 1].offsetLeft - (line.words[j].offsetLeft + line.words[j].offsetWidth);
          if (gap > 10) continue; // a link or bold word sits between: it is not a BeeLine word, so no seam to compare
          seam = Math.max(seam, gdist(gRight(line.words[j]), gLeft(line.words[j + 1])));
          seamPairs++;
        }
        line.words.forEach(function (w) {
          if (w.offsetWidth < 40) return;
          wide++;
          if (gdist(gLeft(w), gRight(w)) < 0.5) flat++;
        });
      });
      var mid = lines[1].words[Math.floor(lines[1].words.length / 2)];
      midInk = gdist(gLeft(mid), inkRgb) < 60;
    }
    R.beeline = { classes: modeClasses(), words: count(".sd-bl-w"), lines: lines.length, startInk: startInk, join: join,
      endDiffersFromInk: endBlue ? gdist(endBlue, rgb(color(longP))) > 40 : false, midInk: midInk,
      gradient: { words: allWords.length, withGradient: withGradient, clipped: clipped, clear: clear, seam: seam, seamPairs: seamPairs, wide: wide, flat: flat },
      inSkipped: count("pre .sd-bl-w, code .sd-bl-w, a .sd-bl-w, h1 .sd-bl-w"), left: leftovers() };

    // rsvp: opens over the page, Space pauses, arrows step, Esc closes and exits the mode
    pick("RSVP");
    var ov = document.querySelector(".sd-rsvp-overlay");
    R.rsvp = { open: !!ov, role: ov && ov.getAttribute("role"), modal: ov && ov.getAttribute("aria-modal"), classes: modeClasses(), left: leftovers() };
    key(" ");
    var w0 = rsvpWord();
    R.rsvp.paused = !!ov.querySelector(".sd-rsvp-btn[aria-label='Play']");
    R.rsvp.word0 = w0.join("");
    R.rsvp.orp = { before: w0[0].length, mid: w0[1].length, len: w0.join("").length };
    key("ArrowRight");
    R.rsvp.word1 = rsvpWord().join("");
    R.rsvp.pos = ov.querySelector(".sd-rsvp-pos").textContent;
    key("ArrowUp");
    R.rsvp.wpm = ov.querySelector(".sd-rsvp-wpm").textContent;
    key("ArrowDown"); key("ArrowDown");
    R.rsvp.wpmDown = ov.querySelector(".sd-rsvp-wpm").textContent;
    key("ArrowUp");
    R.rsvp.stored = [store("sd-read-mode"), store("sd-read-last")];
    // walk every word to see what the reader would show
    var seen = [], atEnd = function () { return /^(\d+) \/ \1$/.test(ov.querySelector(".sd-rsvp-pos").textContent); };
    for (var n = 0; n < 5000 && !/^1 \//.test(ov.querySelector(".sd-rsvp-pos").textContent); n++) key("ArrowLeft");
    for (n = 0; n < 5000; n++) {
      seen.push(rsvpWord().join(""));
      if (atEnd()) break;
      key("ArrowRight");
    }
    R.rsvp.words = seen.length;
    R.rsvp.allWords = " " + seen.join(" ") + " ";
    key("Escape");
    R.rsvp.closed = !document.querySelector(".sd-rsvp-overlay") && !doc.hasAttribute("data-sd-read-mode") && modeClasses().length === 0;
    R.rsvp.triggerOff = t.getAttribute("aria-label") === "Reading mode: Off";

    // rsvp starts from the first prose block in view, not the top of the page
    window.scrollTo(0, document.body.scrollHeight);
    pick("RSVP");
    R.rsvp.startScrolled = rsvpWord().join("");
    key("Escape");
    window.scrollTo(0, 0);
    pick("RSVP");
    R.rsvp.startTop = rsvpWord().join("");
    key("Escape");

    // back to Off: the markup of every mode is gone and the text is the original
    pick("Skim"); pick("Bionic"); pick("BeeLine"); pick("Bionic");
    R.switched = { classes: modeClasses(), left: leftovers() };
    pick("Off");
    R.off = { classes: modeClasses(), attr: doc.hasAttribute("data-sd-read-mode"), restored: sig() === R.base, label: t.getAttribute("aria-label"), left: leftovers(), stored: store("sd-read-mode") };
    key("s");
    R.sAfterOff = doc.getAttribute("data-sd-read-mode");
    key("s");
    pick("Off");

    settings(finish);
  }

  // the Skim settings panel, driven like a reader would: open the menu, click, drag. The rescore after a
  // slider move is debounced, so each step waits for it.
  function settings(done) {
    var pop = document.getElementById("sd-read-pop"), panel = document.querySelector(".sd-skim-panel");
    var range = panel.querySelector("input[type='range']"), select = panel.querySelector("select");
    function opt(name) { return panel.querySelector(".sd-sk-opt[aria-pressed]:nth-child(" + ({ Dim: 1, Heat: 2, Underline: 3 })[name] + ")"); }
    function spans() { return count(".sd-sk"); }
    function wait(fn) { setTimeout(fn, 350); }
    var S = R.settings = {};
    S.hiddenWhenOff = panel.hidden;
    pick("Skim");
    S.base = spans();
    S.defaults = { emph: doc.getAttribute("data-sd-skim"), intensity: range.value, basis: select.value, pressed: ["Dim", "Heat", "Underline"].map(function (n) { return opt(n).getAttribute("aria-pressed"); }) };
    trigger().click();
    S.shownWhenSkim = !panel.hidden && !pop.hidden;
    S.labels = ["Dim", "Heat", "Underline"].map(function (n) { return opt(n).textContent; });
    S.basisOptions = Array.prototype.map.call(select.options, function (o) { return o.value; });

    // emphasis is CSS only: no rescore, the spans stay the same nodes
    var first = document.querySelector(".sd-sk");
    opt("Heat").click();
    S.dimOnly = { attr: doc.getAttribute("data-sd-skim"), stored: store("sd-skim-emph"), sameNode: document.querySelector(".sd-sk") === first,
      heat: (function () { var e = document.querySelector(".sd-sk[data-sk='2']"); return e ? getComputedStyle(e).backgroundColor : null; })() };
    opt("Underline").click();
    S.dimUnderline = { attr: doc.getAttribute("data-sd-skim"), underline: (function () { var e = document.querySelector(".sd-sk[data-sk='2']"); return e ? getComputedStyle(e).textDecorationLine : null; })() };
    opt("Dim").click();
    opt("Underline").click();
    S.none = { attr: doc.getAttribute("data-sd-skim"), stored: store("sd-skim-emph"), spans: spans() };
    opt("Dim").click(); opt("Heat").click();
    S.restored = { attr: doc.getAttribute("data-sd-skim"), stored: store("sd-skim-emph") };

    range.value = "100";
    range.dispatchEvent(new Event("input", { bubbles: true }));
    wait(function () {
      S.full = { spans: spans(), stored: store("sd-skim-intensity"), out: panel.querySelector("output").textContent };
      range.value = "0";
      range.dispatchEvent(new Event("input", { bubbles: true }));
      wait(function () {
        S.zero = { spans: spans(), attr: doc.getAttribute("data-sd-skim"), stored: store("sd-skim-intensity") };
        range.value = "50";
        range.dispatchEvent(new Event("input", { bubbles: true }));
        wait(function () {
          S.back = { spans: spans(), same: spans() === S.base };
          select.value = "surprisal";
          select.dispatchEvent(new Event("change", { bubbles: true }));
          S.surprisal = { spans: spans(), stored: store("sd-skim-basis"), noStack: count(".sd-sk .sd-sk") === 0 };
          select.value = "auto";
          select.dispatchEvent(new Event("change", { bubbles: true }));
          S.auto = { spans: spans(), same: spans() === S.base };
          pick("Off");
          S.off = { restored: sig() === R.base, left: leftovers(), attr: doc.hasAttribute("data-sd-skim"), hiddenAgain: panel.hidden };
          done();
        });
      });
    });
  }

  function finish() {
    var pre = document.createElement("pre");
    pre.id = "sd-test-result";
    pre.textContent = JSON.stringify(R);
    document.body.appendChild(pre);
  }

  window.addEventListener("load", function () {
    setTimeout(function () {
      try { run(); } catch (e) {
        var pre = document.createElement("pre");
        pre.id = "sd-test-result";
        pre.textContent = JSON.stringify({ error: String(e && e.stack || e) });
        document.body.appendChild(pre);
      }
    }, 300);
  });
})();

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
      surprise: count("[class^='sd-s-'], [class^='sd-s1'], [class^='sd-s2']"),
      bionic: count("b.sd-bi"),
      beeline: count(".sd-bl-w"),
      rsvp: count(".sd-rsvp-overlay")
    };
  }
  function modeClasses() {
    return ["skim", "surprise", "bionic", "beeline", "rsvp"].filter(function (m) { return doc.classList.contains("sd-" + m); });
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
      controls: t.getAttribute("aria-controls"), menuHidden: document.getElementById("sd-read-menu").hidden };
    R.base = sig();
    R.noSkimButton = count(".sd-skim") === 0;

    // keyboard: ArrowDown opens and focuses an item, Escape closes and returns focus
    t.focus();
    t.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true, cancelable: true }));
    R.kbOpen = t.getAttribute("aria-expanded") === "true" && document.activeElement.classList.contains("sd-read-item");
    document.activeElement.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true, cancelable: true }));
    R.kbMoved = document.activeElement.getAttribute("role") === "menuitemradio" && document.activeElement.textContent !== "Off";
    document.activeElement.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }));
    R.kbClose = t.getAttribute("aria-expanded") === "false" && document.activeElement === t && document.getElementById("sd-read-menu").hidden;

    // skim (rules)
    pick("Skim");
    var p0 = document.querySelector("p"), keySpan = document.querySelector("span.sd-key");
    R.skim = { classes: modeClasses(), attr: doc.getAttribute("data-sd-read-mode"), checked: document.querySelector(".sd-read-item[aria-checked='true']").textContent,
      keyDiffers: !!keySpan && dist(color(p0), color(keySpan)) > 20, stored: store("sd-read-mode"), left: leftovers() };

    // S toggles the last mode off and on
    key("s"); var afterOff = doc.getAttribute("data-sd-read-mode");
    key("S"); var afterOn = doc.getAttribute("data-sd-read-mode");
    R.sKey = { off: afterOff, on: afterOn };

    // surprise
    pick("Skim (surprise)");
    var lv = {};
    ["s-2", "s-1", "s1", "s2"].forEach(function (l) { lv[l] = count(".sd-" + l); });
    var scoredSpans = lv["s-2"] + lv["s-1"] + lv.s1 + lv.s2;
    var s2 = document.querySelector(".sd-s-2"), s1 = document.querySelector(".sd-s1");
    var text = Array.prototype.map.call(document.querySelectorAll("p, li, td, blockquote"), function (e) { return e.textContent; }).join("\n");
    var res = window.sdSurprise ? window.sdSurprise.analyze(text, { minTokens: 80, intensity: 50 }) : null;
    R.surprise = { classes: modeClasses(), scored: doc.classList.contains("sd-scored"), spans: scoredSpans, levels: lv,
      lang: res && !res.skipped ? res.stats.lang : null, skipped: res && res.skipped ? res.reason : null,
      fadedDarker: !!(s2 && s1) && dist(color(s2), color(s1)) > 20,
      inSkipped: count("pre [class^='sd-s'], code [class^='sd-s'], a [class^='sd-s'], strong [class^='sd-s'], h1 [class^='sd-s'], th [class^='sd-s'], table.sd-frontmatter [class^='sd-s']"),
      label: t.getAttribute("aria-label"), left: leftovers() };
    // a second pass on top must not stack: switching away and back gives the same count
    pick("Skim (surprise)");
    R.surprise.idempotent = count("[class^='sd-s-'], [class^='sd-s1'], [class^='sd-s2']") === scoredSpans;

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
    var join = 0, startInk = null, endBlue = null;
    if (lines.length > 2) {
      var ink = color(longP);
      startInk = dist(color(lines[0].words[0]), ink);
      endBlue = color(lines[0].words[lines[0].words.length - 1]);
      for (var i = 0; i + 1 < lines.length; i++) {
        var a = lines[i].words[lines[i].words.length - 1], b = lines[i + 1].words[0];
        join = Math.max(join, dist(color(a), color(b)));
      }
    }
    R.beeline = { classes: modeClasses(), words: count(".sd-bl-w"), lines: lines.length, startInk: startInk, join: join,
      endDiffersFromInk: endBlue ? dist(endBlue, color(longP)) > 40 : false,
      midInk: lines.length > 1 ? dist(color(lines[1].words[Math.floor(lines[1].words.length / 2)]), color(longP)) < 60 : false,
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
    pick("Skim (surprise)"); pick("Bionic"); pick("BeeLine"); pick("Skim");
    R.switched = { classes: modeClasses(), left: leftovers() };
    pick("Off");
    R.off = { classes: modeClasses(), attr: doc.hasAttribute("data-sd-read-mode"), restored: sig() === R.base, label: t.getAttribute("aria-label"), left: leftovers(), stored: store("sd-read-mode") };
    key("s");
    R.sAfterOff = doc.getAttribute("data-sd-read-mode");
    key("s");

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

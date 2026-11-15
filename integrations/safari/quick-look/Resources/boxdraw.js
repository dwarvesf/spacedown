// boxdraw.js: fenced and indented code blocks drawn with box-drawing characters
// (U+2500-257F) or arrow glyphs (U+2190-21FF, U+25B2-25C5) get the class sd-boxdraw.
// The css hook gives that class a tight line-height (1.2) so vertical lines join; at the
// core 1.5 they show gaps. A plain code block is not marked and keeps its line-height.
// Render time only (no scripts run in the Finder panel). Loaded after ql-render.js.
// Hooks: docs/contract-r1.md.
(function (global) {
  "use strict";
  if (!global.SD) return;

  var DRAWN = /[\u2500-\u257F\u2190-\u21FF\u25B2-\u25C5]/;
  var PRE = /<pre(?: class="([^"]*)")?><code([^>]*)>([\s\S]*?)<\/code><\/pre>/g;

  function mark(html) {
    return html.replace(PRE, function (whole, preClass, codeAttrs, inner) {
      if (!DRAWN.test(inner)) return whole;
      var cls = (preClass ? preClass + " " : "") + "sd-boxdraw";
      return '<pre class="' + cls + '"><code' + codeAttrs + ">" + inner + "</code></pre>";
    });
  }

  global.SD.register({
    id: "boxdraw",
    order: 10,
    transform: function (html, cfg) { return mark(html); },
    css: function (cfg) {
      return "pre.sd-boxdraw, pre.sd-boxdraw code { line-height: 1.2; }";
    }
  });
})(typeof globalThis !== "undefined" ? globalThis : this);

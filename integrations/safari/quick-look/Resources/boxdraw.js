// boxdraw.js: code blocks drawn with box-drawing characters (U+2500-257F) get a tight
// line-height (about 1.2) so the lines join. Loaded after ql-render.js; registers with SD.
// Hooks: docs/contract-r1.md. Stub: registers and changes nothing.
(function (global) {
  "use strict";
  if (!global.SD) return;
  global.SD.register({
    id: "boxdraw",
    order: 10,
    transform: function (html, cfg) { return html; }
  });
})(typeof globalThis !== "undefined" ? globalThis : this);

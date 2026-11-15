// present.js: Present mode (P turns the page into slides, one per H2 or --- break; arrows
// move; Esc exits). Loaded after ql-render.js and xray.js; registers with SD. Hooks:
// docs/contract-r1.md. Stub: registers and changes nothing.
(function (global) {
  "use strict";
  if (!global.SD) return;
  global.SD.register({
    id: "present",
    order: 200,
    transform: function (html, cfg) { return html; },
    key: function (ev, cfg) { return false; },
    reset: function (doc, cfg) {}
  });
})(typeof globalThis !== "undefined" ? globalThis : this);

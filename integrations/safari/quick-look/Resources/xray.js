// xray.js: the Writing X-ray lens (marks dashes, long sentences, filler words, ticket and
// spec IDs; a toolbar toggle). Loaded after ql-render.js; registers with SD. Hooks and
// settings: docs/contract-r1.md. Stub: registers and changes nothing.
(function (global) {
  "use strict";
  if (!global.SD) return;
  global.SD.register({
    id: "xray",
    order: 100,
    transform: function (html, cfg) { return html; }
  });
})(typeof globalThis !== "undefined" ? globalThis : this);

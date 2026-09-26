// Drag a .md file in -> read its text -> hand it to the native messaging host,
// which writes a temp file, runs `spacedown`, and opens the rendered HTML.
//
// Why send the TEXT and not a path: when a file is dropped into a browser, the
// File API exposes only the basename, never the absolute filesystem path (a
// security boundary). So the host cannot re-open "the same file"; we ship the
// content and it renders from a temp copy. Markdown files are tiny, well under
// native messaging's 1MB message ceiling.

const HOST = "foundation.d.spacedown";

// navigator.vendor is "Apple Computer, Inc." in Safari/WebKit and "Google Inc."
// in Chromium (Blink). Used to branch the native-messaging call, whose signature
// differs between the two engines.
const IS_SAFARI = (navigator.vendor || "").includes("Apple");
const RT = (typeof browser !== "undefined" ? browser : chrome).runtime;

const drop = document.getElementById("drop");
const fileInput = document.getElementById("file");
const status = document.getElementById("status");

// Visual-state machine. The native-messaging CONTRACT is unchanged; these
// helpers only drive the look (body state classes + #status content). The
// state classes are styled in dropzone.html: idle (none) / is-rendering /
// is-success / is-error.
const STATE_CLASSES = ["is-rendering", "is-success", "is-error"];
let resetTimer = null;

function setState(state) {
  if (resetTimer) { clearTimeout(resetTimer); resetTimer = null; }
  document.body.classList.remove(...STATE_CLASSES);
  if (state) document.body.classList.add(state);
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => (
    { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]
  ));
}

// setStatus keeps its original (msg, cls) signature so any caller still works.
// cls === "ok" -> success, cls === "err" -> error, else plain status text.
function setStatus(msg, cls) {
  status.textContent = msg;
  status.className = cls || "";
}

// Richer state setters layered on top (used by render()); they keep #status and
// the body state class in sync and render a tasteful inline progress/treatment.
function showRendering(name) {
  setState("is-rendering");
  status.className = "";
  status.innerHTML =
    'Rendering <span class="name">' + escapeHtml(name) + '</span>…' +
    '<span class="bar"><i></i></span>';
}

function showSuccess(name) {
  setState("is-success");
  status.className = "ok";
  status.innerHTML =
    '<span class="name">' + escapeHtml(name) + '</span> rendered, opened in a new tab';
  // Quietly return to idle after a few seconds.
  resetTimer = setTimeout(() => setState(null), 4200);
}

function showError(text) {
  setState("is-error");
  setStatus(text, "err");
}

function render(file) {
  if (!file) return;
  const reader = new FileReader();
  reader.onerror = () => showError("Could not read the file.");
  reader.onload = () => {
    showRendering(file.name);
    sendNative({ filename: file.name, content: reader.result }, (resp) => {
      if (resp && resp.ok) {
        showSuccess(file.name);
      } else {
        showError(
          "Render failed:\n" + (resp && resp.error ? resp.error : "no response from native host") +
          (IS_SAFARI ? "" : "\n\nIs the native host installed? Run integrations/install.sh.")
        );
      }
    });
  };
  reader.readAsText(file);
}

// Cross-engine native messaging.
//   Chromium: sendNativeMessage(hostName, message, callback) -> talks to the
//             external host binary named in the per-browser JSON manifest.
//   Safari:   sendNativeMessage(message) -> Promise; routes to the containing
//             app's SafariWebExtensionHandler (no host name, no JSON manifest).
function sendNative(payload, cb) {
  if (IS_SAFARI) {
    RT.sendNativeMessage(payload)
      .then((resp) => cb(resp))
      .catch((e) => cb({ ok: false, error: String(e && e.message || e) }));
  } else {
    RT.sendNativeMessage(HOST, payload, (resp) => {
      if (chrome.runtime.lastError) {
        cb({ ok: false, error: chrome.runtime.lastError.message });
      } else {
        cb(resp);
      }
    });
  }
}

// --- drag-and-drop wiring ---
["dragenter", "dragover"].forEach((ev) =>
  drop.addEventListener(ev, (e) => {
    e.preventDefault();
    drop.classList.add("hot");
  })
);
["dragleave", "drop"].forEach((ev) =>
  drop.addEventListener(ev, (e) => {
    e.preventDefault();
    if (ev === "dragleave" && e.target !== drop) return;
    drop.classList.remove("hot");
  })
);
drop.addEventListener("drop", (e) => {
  const f = e.dataTransfer.files && e.dataTransfer.files[0];
  render(f);
});

// --- click-to-pick fallback (also keyboard-activated via the button role) ---
drop.addEventListener("click", () => fileInput.click());
drop.addEventListener("keydown", (e) => {
  if (e.key === "Enter" || e.key === " ") { e.preventDefault(); fileInput.click(); }
});
fileInput.addEventListener("change", () => render(fileInput.files[0]));

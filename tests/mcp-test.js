#!/usr/bin/env node
// mcp-test.js: drives `spacedown mcp` over stdin and stdout with a scripted JSON-RPC session and
// prints one "ok: <name>" or "FAIL: <name>" line per check (tests/smoke.sh, section mcp, reads them).
//   node tests/mcp-test.js <path to bin/spacedown> <scratch dir>
// Env: SPACEDOWN_PREFS is read by the server's child renders, so the caller sets it.
"use strict";
const { spawn } = require("child_process");
const fs = require("fs");
const path = require("path");

const SPACEDOWN = process.argv[2];
const TMP = process.argv[3];
const FIX = path.join(__dirname, "fixture");
const results = [];
function check(name, cond, detail) {
  results.push(cond);
  console.log((cond ? "ok: " : "FAIL: ") + name + (!cond && detail !== undefined ? " [" + String(detail).slice(0, 300) + "]" : ""));
}

const child = spawn(SPACEDOWN, ["mcp"], { stdio: ["pipe", "pipe", "pipe"], env: process.env });
let stderr = "";
child.stderr.on("data", (d) => { stderr += d; });
let buf = "", waiting = null;
const queue = [];
child.stdout.on("data", (d) => {
  buf += d;
  let i;
  while ((i = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, i);
    buf = buf.slice(i + 1);
    if (waiting) { const w = waiting; waiting = null; w(line); } else queue.push(line);
  }
});
let exited = null;
child.on("exit", (code) => { exited = code; if (waiting) { const w = waiting; waiting = null; w(null); } });
function readLine() {
  if (queue.length) return Promise.resolve(queue.shift());
  if (exited !== null) return Promise.resolve(null);
  return new Promise((resolve) => { waiting = resolve; setTimeout(() => { if (waiting === resolve) { waiting = null; resolve(null); } }, 120000); });
}
let nextId = 1;
async function rpc(method, params) {
  const id = nextId++;
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  const line = await readLine();
  let msg = null;
  try { msg = JSON.parse(line); } catch (e) { /* null */ }
  if (msg && msg.id !== id) msg = null;
  return msg;
}
async function call(name, args) {
  const r = await rpc("tools/call", { name, arguments: args });
  return r && r.result ? r.result : r;
}
const isErr = (r) => !!r && r.isError === true && r.content && r.content[0] && r.content[0].type === "text" && r.content[0].text.length > 0;

(async () => {
  // initialize and the version handshake
  let r = await rpc("initialize", { protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "smoke", version: "0" } });
  check("initialize pins protocol 2025-11-25, names the server, offers tools",
    r && r.result && r.result.protocolVersion === "2025-11-25" && r.result.serverInfo.name === "spacedown" && !!r.result.capabilities.tools, JSON.stringify(r));
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
  r = await rpc("initialize", { protocolVersion: "1999-01-01" });
  check("initialize with an unknown version answers with the server's own", r && r.result && r.result.protocolVersion === "2025-11-25", JSON.stringify(r));

  // tools/list
  r = await rpc("tools/list", {});
  const tools = (r && r.result && r.result.tools) || [];
  check("tools/list names render, shot and lint", ["render", "shot", "lint"].every((n) => tools.some((t) => t.name === n)) && tools.length === 3, tools.map((t) => t.name));
  check("every tool has a strict object input schema (additionalProperties false, no top-level oneOf)",
    tools.length === 3 && tools.every((t) => t.inputSchema && t.inputSchema.type === "object" && t.inputSchema.additionalProperties === false &&
      !t.inputSchema.oneOf && !t.inputSchema.anyOf && !t.inputSchema.allOf && t.description && t.outputSchema));

  // lint, with the app settings empty (every rule on)
  const lintFile = path.join(FIX, "mcp-lint.md");
  let res = await call("lint", { path: lintFile });
  let sc = res && res.structuredContent;
  const by = (rule) => ((sc && sc.findings) || []).filter((f) => f.rule === rule);
  check("lint returns structured findings and text content that parses to the same object",
    !!sc && res.isError === false && JSON.stringify(JSON.parse(res.content[0].text)) === JSON.stringify(sc), JSON.stringify(res));
  check("lint finds the filler word, dash, ticket ID and long sentence, each with rule, line, excerpt, message",
    !!sc && by("filler").length === 1 && by("dash").length === 1 && by("ticket-id").length === 1 && by("long-sentence").length === 1 &&
    sc.findings.every((f) => typeof f.rule === "string" && (f.line === null || Number.isInteger(f.line)) && typeof f.excerpt === "string" && typeof f.message === "string"),
    sc && JSON.stringify(sc.findings.map((f) => f.rule)));
  check("lint maps findings to source lines (really on 6, dash and ticket on 8, long sentence on 10)",
    !!sc && by("filler")[0].line === 6 && by("dash")[0].line === 8 && by("ticket-id")[0].line === 8 && by("long-sentence")[0].line === 10, sc && JSON.stringify(sc.findings.map((f) => f.rule + ":" + f.line)));
  check("lint ignores a dash and a filler word inside inline code and a code fence",
    !!sc && by("dash").length === 1 && by("filler").length === 1 && sc.findings.every((f) => f.line !== 13));
  res = await call("lint", { text: "A clean line.\n\nAnother one, really.\n" });
  check("lint takes text instead of a path", !!res && !!res.structuredContent && res.structuredContent.findings.length === 1 && res.structuredContent.findings[0].line === 3, JSON.stringify(res));

  res = await call("lint", { path: lintFile });
  sc = res.structuredContent;
  check("lint reports the active rules and the sentence limit", !!sc && sc.rules.length === 4 && sc.sentence_word_limit === 25, sc && JSON.stringify(sc.rules));

  // render
  const outHtml = path.join(TMP, "mcp-render.html");
  res = await call("render", { path: path.join(FIX, "mcp-lint.md"), out: outHtml });
  check("render writes the HTML and returns its path (the CLI's stdout line)",
    !!res && res.isError === false && res.structuredContent.html_path === outHtml && res.structuredContent.stdout[0] === outHtml && fs.existsSync(outHtml) && /<h1[^>]*>Lint fixture/.test(fs.readFileSync(outHtml, "utf8")), JSON.stringify(res));
  res = await call("render", { text: "# From text\n\nBody.", title: "T", font_mode: "paper" });
  const tp = res && res.structuredContent && res.structuredContent.html_path;
  check("render takes text and a font mode", !!tp && fs.existsSync(tp) && /From text/.test(fs.readFileSync(tp, "utf8")), JSON.stringify(res));

  // shot (needs Helium, Chrome or Chromium)
  const png = path.join(TMP, "mcp-shot.png");
  res = await call("shot", { path: path.join(FIX, "mcp-shot.md"), out: path.join(TMP, "mcp-shot.html"), png, width: 900 });
  if (isErr(res) && /none found/.test(res.content[0].text)) {
    console.log("  skip: no Helium, Chrome or Chromium installed (shot)");
  } else {
    const w = (res && res.structuredContent && res.structuredContent.warnings) || [];
    check("shot writes a PNG and returns its path", !!res && res.isError === false && res.structuredContent.png_path === png && fs.existsSync(png) && fs.statSync(png).size > 1000, JSON.stringify(res));
    check("shot returns the wide-table and red-KaTeX WARN lines as structured warnings",
      w.some((x) => x.kind === "wide_table" && x.width_px > x.container_px && x.cell && x.cell.inline_code === true) && w.some((x) => x.kind === "katex" && x.count >= 1), JSON.stringify(w));
  }

  // bad input comes back as an error result, and the server keeps serving
  res = await call("lint", { path: path.join(TMP, "missing.md") });
  check("a missing file is an isError result that says what failed", isErr(res) && /not found/.test(res.content[0].text), JSON.stringify(res));
  res = await call("lint", { path: lintFile, bogus: 1 });
  check("an unknown argument is rejected", isErr(res) && /unknown argument: bogus/.test(res.content[0].text), JSON.stringify(res));
  res = await call("render", { path: lintFile, text: "x" });
  check("path and text together are rejected", isErr(res) && /exactly one of path or text/.test(res.content[0].text), JSON.stringify(res));
  res = await call("render", {});
  check("neither path nor text is rejected", isErr(res), JSON.stringify(res));
  res = await call("shot", { text: "x", width: "wide" });
  check("a wrong argument type is rejected", isErr(res) && /width must be an integer/.test(res.content[0].text), JSON.stringify(res));
  res = await call("render", { text: "x", font_mode: "comic" });
  check("a bad enum value is rejected", isErr(res) && /font_mode must be one of/.test(res.content[0].text), JSON.stringify(res));
  r = await rpc("tools/call", { name: "nope", arguments: {} });
  check("an unknown tool is a JSON-RPC error -32602", !!r && !!r.error && r.error.code === -32602, JSON.stringify(r));
  r = await rpc("no/such/method", {});
  check("an unknown method is a JSON-RPC error -32601", !!r && !!r.error && r.error.code === -32601, JSON.stringify(r));
  child.stdin.write("this is not json\n");
  let bad = null;
  try { bad = JSON.parse(await readLine()); } catch (e) { /* null */ }
  check("malformed JSON is a -32700 parse error with a null id", !!bad && bad.error && bad.error.code === -32700 && bad.id === null, JSON.stringify(bad));
  r = await rpc("ping", {});
  check("the server still answers after bad input", !!r && !!r.result && exited === null, JSON.stringify(r));

  // closing stdin ends the server cleanly
  child.stdin.end();
  const code = await new Promise((resolve) => { if (exited !== null) resolve(exited); else { child.on("exit", resolve); setTimeout(() => resolve("timeout"), 10000); } });
  check("closing stdin exits 0", code === 0, code);

  // the user's settings apply: a second server whose app settings switch dashes off and the limit down
  const prefs = process.argv[4];
  if (prefs) {
    const second = spawn(SPACEDOWN, ["mcp"], { stdio: ["pipe", "pipe", "pipe"], env: Object.assign({}, process.env, { SPACEDOWN_PREFS: prefs }) });
    let out = "";
    second.stdout.on("data", (d) => { out += d; });
    second.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "lint", arguments: { path: lintFile } } }) + "\n");
    second.stdin.end();
    await new Promise((resolve) => { second.on("exit", resolve); setTimeout(resolve, 60000); });
    let sr = null;
    try { sr = JSON.parse(out.split("\n")[0]).result.structuredContent; } catch (e) { /* null */ }
    check("lint applies the app's settings (dashes off gives no dash finding, the limit applies)",
      !!sr && sr.rules.indexOf("dash") < 0 && !sr.findings.some((f) => f.rule === "dash") && sr.sentence_word_limit === 40 &&
      sr.findings.some((f) => f.rule === "filler") && !sr.findings.some((f) => f.rule === "long-sentence"), out.slice(0, 300));
  }

  // the config snippet in the README, run as an MCP client runs it: its command resolved on PATH
  const readme = process.argv[5];
  if (readme) {
    let cfg = null;
    const m = /```json\n([^`]*"mcpServers"[^`]*)```/.exec(fs.readFileSync(readme, "utf8"));
    try { cfg = JSON.parse(m[1]).mcpServers.spacedown; } catch (e) { /* null */ }
    let tl = null;
    if (cfg) {
      const third = spawn(cfg.command, cfg.args, { stdio: ["pipe", "pipe", "pipe"], env: process.env });
      let out = "";
      third.on("error", () => {});
      third.stdout.on("data", (d) => { out += d; });
      third.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-11-25" } }) + "\n");
      third.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: 2, method: "tools/list" }) + "\n");
      third.stdin.end();
      await new Promise((resolve) => { third.on("exit", resolve); third.on("error", resolve); setTimeout(resolve, 60000); });
      try { tl = JSON.parse(out.split("\n")[1]).result.tools.map((t) => t.name).join(","); } catch (e) { /* null */ }
    }
    check("the README config snippet {command: spacedown, args: [mcp]} starts a working server",
      !!cfg && cfg.command === "spacedown" && JSON.stringify(cfg.args) === '["mcp"]' && tl === "render,shot,lint", JSON.stringify(cfg) + " " + tl);
  }
  process.exit(results.every(Boolean) ? 0 : 1);
})().catch((e) => { console.log("FAIL: driver error: " + e.message); process.exit(1); });

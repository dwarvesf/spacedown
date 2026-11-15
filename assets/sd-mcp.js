// sd-mcp.js: the spacedown MCP server. `spacedown mcp` runs it under `osascript -l JavaScript`,
// so it needs nothing beyond macOS. It speaks MCP over stdio: JSON-RPC 2.0, one message per line
// on stdin, one per line on stdout; diagnostics go to stderr.
//
//   osascript -l JavaScript assets/sd-mcp.js self=<path to bin/spacedown> version=<x.y.z>
//
// Protocol: 2025-11-25 (also answers 2025-06-18). It serves tools/list and tools/call whether or
// not initialize came first, so a client built on the stateless 2026-07-28 revision works too.
// Tools (thin wrappers: each runs bin/spacedown and reads its stdout contract and stderr):
//   render  Markdown path or text in, rendered HTML path out
//   shot    render plus a headless screenshot; WARN lines come back as structured warnings
//   lint    the Writing X-ray findings (assets/sd-cli-render.js, --lint-json), settings applied
// A bad input is a tool result with isError true, never a crash. Unknown tool, unknown method and
// malformed JSON are JSON-RPC errors. Contract: README "MCP server".
ObjC.import("Foundation");

var SUPPORTED = ["2025-11-25", "2025-06-18"];
var OUT_DIR = "/tmp/spacedown";

function run(argv) {
  var opt = {};
  argv.forEach(function (a) { var i = a.indexOf("="); if (i > 0) opt[a.slice(0, i)] = a.slice(i + 1); });
  var SELF = opt.self;
  var FM = $.NSFileManager.defaultManager;
  var seq = 0;

  function logErr(msg) {
    $.NSFileHandle.fileHandleWithStandardError.writeData($("spacedown mcp: " + msg + "\n").dataUsingEncoding($.NSUTF8StringEncoding));
  }
  function send(msg) {
    $.NSFileHandle.fileHandleWithStandardOutput.writeData($(JSON.stringify(msg) + "\n").dataUsingEncoding($.NSUTF8StringEncoding));
  }
  function readText(path) {
    var s = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
    return s ? ObjC.unwrap(s) : "";
  }
  function writeText(path, text) {
    return $(text).writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
  }
  function isFile(path) {
    var dir = Ref();
    return FM.fileExistsAtPathIsDirectory(path, dir) && !dir[0];
  }

  // ---- tool definitions ----
  // No top-level oneOf: some model APIs reject it in a tool schema. "path or text, exactly one"
  // is said in the description and checked in validate().
  var SRC_PROPS = {
    path: { type: "string", minLength: 1, description: "Path to a Markdown file. Give this or text, not both." },
    text: { type: "string", minLength: 1, description: "Markdown source as a string. Give this or path, not both. Relative images resolve against the working directory of the server." }
  };
  var RENDER_PROPS = {
    out: { type: "string", minLength: 1, description: "Output HTML path. Default: /tmp/spacedown/<slug>.html." },
    title: { type: "string", minLength: 1, description: "Page title. Default: the file name without its extension." },
    font_mode: { type: "string", enum: ["ia", "tm", "paper", "read", "mono"], description: "Reading look. Default ia." }
  };
  function props() {
    var o = {};
    for (var i = 0; i < arguments.length; i++) for (var k in arguments[i]) o[k] = arguments[i][k];
    return o;
  }
  var WARNING = {
    type: "object",
    properties: {
      kind: { type: "string", enum: ["wide_table", "katex"] },
      message: { type: "string" }
    },
    required: ["kind", "message"]
  };
  var TOOLS = [
    {
      name: "render",
      title: "Render Markdown to HTML",
      description: "Render Markdown to a self-contained HTML page through Spacedown's Quick Look core (tables, code, callouts, frontmatter, KaTeX math). Give path or text, exactly one. Returns the HTML file path. Open it or pass it to shot to see it.",
      inputSchema: { type: "object", properties: props(SRC_PROPS, RENDER_PROPS), additionalProperties: false },
      outputSchema: { type: "object", properties: { html_path: { type: "string" }, stdout: { type: "array", items: { type: "string" } } }, required: ["html_path", "stdout"] },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false }
    },
    {
      name: "shot",
      title: "Render and screenshot Markdown",
      description: "Render Markdown, then screenshot the page in a private headless browser (Helium, Chrome or Chromium) so you can look at the result. Returns the PNG path, the HTML path and warnings: tables wider than the page (scroll sideways) and KaTeX that renders in red. Give path or text, exactly one.",
      inputSchema: {
        type: "object",
        properties: props(SRC_PROPS, RENDER_PROPS, {
          png: { type: "string", minLength: 1, description: "Output PNG path. Default: next to the HTML." },
          width: { type: "integer", minimum: 320, maximum: 4000, description: "Window width in px. Default 1300." },
          height: { type: "integer", minimum: 200, maximum: 8000, description: "Window height in px. Default 1100." },
          offline: { type: "boolean", description: "Block the network for the screenshot browser, as for a reader with no connection." }
        }),
        additionalProperties: false
      },
      outputSchema: {
        type: "object",
        properties: { png_path: { type: "string" }, html_path: { type: "string" }, stdout: { type: "array", items: { type: "string" } }, warnings: { type: "array", items: WARNING } },
        required: ["png_path", "html_path", "stdout", "warnings"]
      },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false }
    },
    {
      name: "lint",
      title: "Lint Markdown with the Writing X-ray",
      description: "Run the Writing X-ray rules on Markdown and return findings: em and en dashes, sentences over the word limit, filler words, ticket and spec IDs. The Spacedown app's settings apply (rules switched off there give no findings). Text in code and comments is ignored. Give path or text, exactly one.",
      inputSchema: { type: "object", properties: props(SRC_PROPS), additionalProperties: false },
      outputSchema: {
        type: "object",
        properties: {
          rules: { type: "array", items: { type: "string" } },
          sentence_word_limit: { type: "integer" },
          findings: {
            type: "array",
            items: {
              type: "object",
              properties: {
                rule: { type: "string", enum: ["dash", "long-sentence", "filler", "ticket-id"] },
                line: { type: ["integer", "null"] },
                excerpt: { type: "string" },
                message: { type: "string" }
              },
              required: ["rule", "line", "excerpt", "message"]
            }
          }
        },
        required: ["rules", "findings"]
      },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false }
    }
  ];

  // ---- strict input check, against the schema above ----
  function validate(tool, args) {
    var schema = tool.inputSchema, p = schema.properties, errs = [];
    if (args === undefined || args === null) args = {};
    if (typeof args !== "object" || Array.isArray(args)) return ["arguments must be an object"];
    Object.keys(args).forEach(function (k) {
      var d = p[k], v = args[k];
      if (!d) { errs.push("unknown argument: " + k); return; }
      if (d.type === "string") {
        if (typeof v !== "string") errs.push(k + " must be a string");
        else if (d.minLength && v.length < d.minLength) errs.push(k + " must not be empty");
        else if (d.enum && d.enum.indexOf(v) < 0) errs.push(k + " must be one of " + d.enum.join(", "));
      } else if (d.type === "integer") {
        if (typeof v !== "number" || Math.floor(v) !== v) errs.push(k + " must be an integer");
        else if (v < d.minimum || v > d.maximum) errs.push(k + " must be between " + d.minimum + " and " + d.maximum);
      } else if (d.type === "boolean") {
        if (typeof v !== "boolean") errs.push(k + " must be true or false");
      }
    });
    if (p.path) {
      var n = ["path", "text"].filter(function (k) { return args[k] !== undefined; }).length;
      if (n !== 1) errs.push("give exactly one of path or text");
    }
    return errs;
  }

  // ---- run bin/spacedown ----
  // stdout and stderr go to files, not pipes, so a chatty child can never fill a pipe and block.
  // stdin is /dev/null: the child must never read the JSON-RPC channel.
  function runCli(args, env) {
    seq++;
    var base = OUT_DIR + "/.mcp-io-" + $.NSProcessInfo.processInfo.processIdentifier + "-" + seq;
    FM.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(OUT_DIR, true, $(), null);
    FM.createFileAtPathContentsAttributes(base + ".out", $(), $());
    FM.createFileAtPathContentsAttributes(base + ".err", $(), $());
    var task = $.NSTask.alloc.init;
    task.launchPath = SELF;
    task.arguments = args;
    var e = $.NSMutableDictionary.dictionaryWithDictionary($.NSProcessInfo.processInfo.environment);
    Object.keys(env || {}).forEach(function (k) { e.setObjectForKey(env[k], k); });
    task.environment = e;
    task.standardInput = $.NSFileHandle.fileHandleWithNullDevice;
    var fo = $.NSFileHandle.fileHandleForWritingAtPath(base + ".out");
    var fe = $.NSFileHandle.fileHandleForWritingAtPath(base + ".err");
    task.standardOutput = fo;
    task.standardError = fe;
    var err = Ref();
    var started = task.launchAndReturnError(err);
    var code = 2;
    if (started) {
      // NSTask.waitUntilExit is not bridged to JXA: poll
      while (task.running) $.NSThread.sleepForTimeInterval(0.02);
      code = Number(task.terminationStatus);
    }
    fo.closeAndReturnError(Ref()); fe.closeAndReturnError(Ref());
    var out = readText(base + ".out"), errText = readText(base + ".err");
    FM.removeItemAtPathError(base + ".out", null);
    FM.removeItemAtPathError(base + ".err", null);
    if (!started) errText = "spacedown: cannot start " + SELF;
    function lines(t) { return t.split("\n").filter(function (l) { return l !== ""; }); }
    return { code: code, stdout: lines(out), stderr: lines(errText).map(function (l) { return l.replace(/^spacedown: /, ""); }) };
  }

  function toolError(text) { return { content: [{ type: "text", text: text }], isError: true }; }
  function toolOk(structured) { return { content: [{ type: "text", text: JSON.stringify(structured) }], structuredContent: structured, isError: false }; }
  function failure(what, r) {
    var detail = r.stderr.length ? r.stderr.join("\n") : "(no output)";
    return toolError(what + " failed (exit " + r.code + "):\n" + detail);
  }

  // The source file for a call: the given path, or the text written to a file of its own.
  function sourceOf(args) {
    if (args.path !== undefined) {
      var name = args.path.split("/").pop().replace(/\.(md|markdown)$/i, "");
      return { file: args.path, slug: slugify(name) || "page" };
    }
    seq++;
    var slug = "mcp-" + Math.floor(Date.now() / 1000) + "-" + $.NSProcessInfo.processInfo.processIdentifier + "-" + seq;
    FM.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(OUT_DIR, true, $(), null);
    var file = OUT_DIR + "/" + slug + ".md";
    writeText(file, args.text);
    return { file: file, slug: slug };
  }
  function slugify(s) { return s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, ""); }

  function renderArgs(args, src, htmlPath) {
    var a = [src.file, "--no-open", "--out", htmlPath];
    if (args.title !== undefined) a.push("--title", args.title);
    if (args.font_mode !== undefined) a.push("--font-mode", args.font_mode);
    return a;
  }

  // "WARN wide table #1: 1500 px wide in a 900 px container (scrolls sideways at 1300px); widest
  // unbreakable cell row 2 col 3: "text" (inline code)" and "WARN katex: 2 formula part(s) ..."
  function parseWarnings(stderr) {
    var out = [];
    stderr.forEach(function (l) {
      var m = /^WARN wide table #(\d+): (\d+) px wide in a (\d+) px container[^;]*(?:; widest unbreakable cell row (\d+) col (\d+): "(.*?)"( \(inline code\))?)?$/.exec(l);
      if (m) {
        var w = { kind: "wide_table", message: l.replace(/^WARN /, ""), table: +m[1], width_px: +m[2], container_px: +m[3] };
        if (m[4]) { w.cell = { row: +m[4], column: +m[5], text: m[6], inline_code: !!m[7] }; }
        out.push(w);
      } else if (/^WARN katex: /.test(l)) {
        var k = /^WARN katex: (\d+) formula/.exec(l);
        out.push({ kind: "katex", message: l.replace(/^WARN /, ""), count: k ? +k[1] : 0 });
      }
    });
    return out;
  }

  var HANDLERS = {
    render: function (args) {
      var src = sourceOf(args);
      var html = args.out !== undefined ? args.out : OUT_DIR + "/" + src.slug + ".html";
      var r = runCli(renderArgs(args, src, html));
      if (r.code !== 0 || r.stdout.length < 1) return failure("render", r);
      return toolOk({ html_path: r.stdout[0], stdout: r.stdout });
    },
    shot: function (args) {
      var src = sourceOf(args);
      var html = args.out !== undefined ? args.out : OUT_DIR + "/" + src.slug + ".html";
      var png = args.png !== undefined ? args.png : html.replace(/\.html?$/i, "") + ".png";
      var a = renderArgs(args, src, html).concat(["--shot", png]);
      if (args.width !== undefined) a.push("--shot-width", String(args.width));
      if (args.height !== undefined) a.push("--shot-height", String(args.height));
      if (args.offline) a.push("--offline");
      var r = runCli(a);
      if (r.code !== 0 || r.stdout.length < 2) return failure("shot", r);
      return toolOk({ png_path: r.stdout[1], html_path: r.stdout[0], stdout: r.stdout, warnings: parseWarnings(r.stderr) });
    },
    lint: function (args) {
      var src = sourceOf(args);
      var json = OUT_DIR + "/mcp-lint-" + src.slug + ".json";
      FM.removeItemAtPathError(json, null);
      // The page itself is a by-product here: no fonts or images embedded, to keep it quick.
      var r = runCli([src.file, "--no-open", "--out", OUT_DIR + "/mcp-lint-" + src.slug + ".html", "--lint-json", json],
        { SPACEDOWN_EMBED_FONTS: "0", SPACEDOWN_EMBED_IMAGES: "0" });
      if (r.code !== 0) return failure("lint", r);
      var data;
      try { data = JSON.parse(readText(json)); } catch (e) { data = null; }
      if (!data || !data.findings) return toolError("lint failed: the renderer wrote no findings file");
      return toolOk({ rules: data.rules, sentence_word_limit: data.sentenceWordLimit, findings: data.findings.map(function (f) {
        return { rule: f.rule, line: f.line, excerpt: f.excerpt, message: f.message };
      }) });
    }
  };

  // ---- JSON-RPC ----
  function reply(id, result) { send({ jsonrpc: "2.0", id: id, result: result }); }
  function fail(id, code, message) { send({ jsonrpc: "2.0", id: id, error: { code: code, message: message } }); }

  function handle(msg) {
    if (msg === null || typeof msg !== "object" || Array.isArray(msg) || msg.jsonrpc !== "2.0" || typeof msg.method !== "string") {
      // a response to something we never asked, or not JSON-RPC at all
      if (msg && typeof msg === "object" && !Array.isArray(msg) && msg.method === undefined && ("result" in msg || "error" in msg)) return;
      return fail(msg && typeof msg === "object" && !Array.isArray(msg) && (typeof msg.id === "string" || typeof msg.id === "number") ? msg.id : null, -32600, "Invalid Request");
    }
    var isRequest = msg.id !== undefined && msg.id !== null;
    var params = msg.params || {};
    if (!isRequest) return; // a notification (notifications/initialized, cancelled, ...): no reply
    switch (msg.method) {
      case "initialize":
        var want = params.protocolVersion;
        return reply(msg.id, {
          protocolVersion: SUPPORTED.indexOf(want) >= 0 ? want : SUPPORTED[0],
          capabilities: { tools: { listChanged: false } },
          serverInfo: { name: "spacedown", title: "Spacedown", version: opt.version || "0" },
          instructions: "Spacedown renders Markdown the way a person will read it. Use lint to catch dashes, long sentences, filler and ticket IDs, render for the HTML page, and shot to look at the page as a PNG (it also warns about wide tables and red KaTeX)."
        });
      case "ping":
        return reply(msg.id, {});
      case "tools/list":
        return reply(msg.id, { tools: TOOLS });
      case "tools/call":
        if (typeof params.name !== "string") return fail(msg.id, -32602, "Invalid params: name is required");
        var tool = TOOLS.filter(function (t) { return t.name === params.name; })[0];
        if (!tool) return fail(msg.id, -32602, "Unknown tool: " + params.name);
        var errs = validate(tool, params.arguments);
        if (errs.length) return reply(msg.id, toolError("Invalid arguments for " + tool.name + ": " + errs.join("; ")));
        try {
          return reply(msg.id, HANDLERS[tool.name](params.arguments || {}));
        } catch (e) {
          return reply(msg.id, toolError(tool.name + " failed: " + (e && e.message ? e.message : String(e))));
        }
      default:
        return fail(msg.id, -32601, "Method not found: " + msg.method);
    }
  }

  function onLine(line) {
    if (line.trim() === "") return;
    var msg;
    try { msg = JSON.parse(line); } catch (e) { return fail(null, -32700, "Parse error"); }
    try { handle(msg); } catch (e) {
      logErr("internal error: " + (e && e.message ? e.message : String(e)));
      if (msg && msg.id !== undefined && msg.id !== null) fail(msg.id, -32603, "Internal error");
    }
  }

  // ---- stdin loop: newline-delimited JSON; a multi-byte character split across reads waits ----
  var stdin = $.NSFileHandle.fileHandleWithStandardInput;
  var pending = $.NSMutableData.data, text = "";
  while (true) {
    var chunk = stdin.availableData;
    if (Number(chunk.length) === 0) break; // EOF: the client closed our stdin
    pending.appendData(chunk);
    var s = $.NSString.alloc.initWithDataEncoding(pending, $.NSUTF8StringEncoding);
    if (!s || ObjC.unwrap(s) === undefined) continue;
    text += ObjC.unwrap(s);
    pending = $.NSMutableData.data;
    var at;
    while ((at = text.indexOf("\n")) >= 0) {
      var line = text.slice(0, at);
      text = text.slice(at + 1);
      onLine(line);
    }
  }
  if (text.trim() !== "") onLine(text);
  return "";
}

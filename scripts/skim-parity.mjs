#!/usr/bin/env node
// skim-parity: prove the Skim engine in assets/skim-surprise.html scores like skimgram.
//
//   node scripts/skim-parity.mjs                      port against the committed goldens (no upstream needed)
//   node scripts/skim-parity.mjs --upstream <clone>   port against upstream run live from a skimgram clone
//   node scripts/skim-parity.mjs --upstream <clone> --write-golden
//                                                     same, then rewrite tests/fixtures/skim/golden/*.json
//   --freq-dir <dir>   directory whose node_modules holds most-common-words-by-language and hanzi
//                      (default: the clone itself). Needed with --upstream for the word lists.
//
// Every file in tests/fixtures/skim is scored by both sides under each basis (auto, surprisal, gain)
// and each intensity (0, 25, 50, 100). Per token it compares key, kind, offsets, level, the raw
// score and the smoothed score (scores to 1e-9). It also compares the page flattening, including
// the 400k character cap, and the two word lists. Exit 0 only when every mismatch count is 0.
//
// Upstream is read, never built: the pure core files (src/core/*.ts, src/dom/walker.ts) are copied
// to a temp directory with their import paths rewritten, and run with node --experimental-strip-types.
// The clone is not touched. The one patch is on that copy of scorer.ts: its return gains a debug
// field so the raw and smoothed scores can be read.
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import vm from "node:vm";

const PINNED = "4ebb78a";
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const FIXTURES = path.join(ROOT, "tests/fixtures/skim");
const GOLDEN = path.join(FIXTURES, "golden");
const BASES = ["auto", "surprisal", "gain"];
const INTENSITIES = [0, 25, 50, 100];
const MIN_TOKENS = 80;
const TOLERANCE = 1e-9;
const KIND_CODE = { cjk: "c", word: "w", number: "n", punct: "p", space: "s" };
const CODE_KIND = Object.fromEntries(Object.entries(KIND_CODE).map(([k, v]) => [v, k]));

function usage(code) {
  console.log("Usage: skim-parity.mjs [--upstream <skimgram clone>] [--freq-dir <dir>] [--write-golden]");
  process.exit(code);
}

const args = { upstream: "", freqDir: "", writeGolden: false };
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (a === "--upstream") args.upstream = process.argv[++i] ?? usage(2);
  else if (a === "--freq-dir") args.freqDir = process.argv[++i] ?? usage(2);
  else if (a === "--write-golden") args.writeGolden = true;
  else if (a === "-h" || a === "--help") usage(0);
  else usage(2);
}
if (args.writeGolden && !args.upstream) { console.error("skim-parity: --write-golden needs --upstream"); process.exit(2); }

// The TypeScript files need type stripping, which node 22 only does behind a flag.
if (args.upstream && !process.execArgv.includes("--experimental-strip-types")) {
  const r = spawnSync(process.execPath, ["--experimental-strip-types", "--no-warnings", ...process.argv.slice(1)], { stdio: "inherit" });
  process.exit(r.status ?? 2);
}

const sha = (s) => createHash("sha256").update(s).digest("hex");

// ---- the port, run in a bare vm context exactly as the page script would be ----
function loadPort() {
  const html = readFileSync(path.join(ROOT, "assets/skim-surprise.html"), "utf8");
  const ctx = { window: {} };
  vm.createContext(ctx);
  vm.runInContext(html.slice(html.indexOf("<script>") + 8, html.lastIndexOf("</script>")), ctx);
  const S = ctx.window.sdSurprise;
  if (!S) throw new Error("assets/skim-surprise.html did not define window.sdSurprise");
  const list = (name) => JSON.parse(html.match(new RegExp(`var ${name} = ("[^"]*");`))[1]);
  return {
    name: "port",
    tokenize: S.tokenize,
    flatten: (strings) => { const f = S.flatten(strings); return { text: f.text, starts: f.starts }; },
    analyze(text, o) {
      const r = S.analyze(text, o);
      if (r.skipped) return { skipped: true, reason: r.reason };
      return { skipped: false, basis: r.stats.basis, spread: r.stats.spread, lang: r.stats.lang, levels: r.levels, seqIdx: r.scores.seqIdx, raw: r.scores.raw, smoothed: r.scores.smoothed };
    },
    lists: { en: list("EN_WORDS"), cjk: list("CJK_CHARS") },
  };
}

// ---- upstream, staged from a clone ----
function buildLists(freqDir) {
  const nm = path.join(freqDir, "node_modules");
  const enPkg = path.join(nm, "most-common-words-by-language");
  const zhPkg = path.join(nm, "hanzi");
  if (!existsSync(enPkg) || !existsSync(zhPkg)) {
    throw new Error(`word lists not found: ${enPkg} and ${zhPkg} are needed (npm pack most-common-words-by-language@3.0.14 hanzi@3.2.0, unpack under <dir>/node_modules/<name>/, then pass --freq-dir <dir>)`);
  }
  // The same two reads and filters as upstream scripts/frequency-plugin.ts.
  const EN_ALLOWED = /^[a-z0-9'-]+$/;
  const en = [];
  for (const line of readFileSync(path.join(enPkg, "build/resources/english.txt"), "utf8").split("\n")) {
    const word = line.trim();
    if (!word || word.length > 20 || !EN_ALLOWED.test(word)) continue;
    en.push(word);
    if (en.length >= 3000) break;
  }
  const zhText = createRequire(import.meta.url)(path.join(zhPkg, "lib/data/frequencyjunda.txt.js"));
  const body = zhText.replace(/^module\.exports\s*=\s*`/, "").replace(/`;?\s*$/, "");
  const zh = [];
  for (const line of body.split("\n")) {
    const char = line.split("\t")[1]?.trim() ?? "";
    if ([...char].length !== 1) continue;
    zh.push(char);
    if (zh.length >= 2000) break;
  }
  const version = (dir) => JSON.parse(readFileSync(path.join(dir, "package.json"), "utf8")).version;
  return { en: en.join(" "), cjk: zh.join(""), versions: { enPkg: version(enPkg), zhPkg: version(zhPkg) } };
}

function fakeRoot(strings) {
  const nodes = strings.map((s) => ({ nodeValue: s, parentElement: { tagName: "P", closest: () => null } }));
  return {
    ownerDocument: {
      createTreeWalker(_root, _what, filter) {
        let i = -1;
        return {
          currentNode: null,
          nextNode() {
            while (++i < nodes.length) {
              if (filter.acceptNode(nodes[i]) === 1) { this.currentNode = nodes[i]; return nodes[i]; }
            }
            return null;
          },
        };
      },
    },
  };
}

async function loadUpstream(clone, freqDir) {
  const head = spawnSync("git", ["-C", clone, "rev-parse", "--short", "HEAD"], { encoding: "utf8" });
  const sha7 = head.stdout.trim();
  if (head.status !== 0 || sha7 !== PINNED) {
    throw new Error(`upstream clone is at ${sha7 || "unknown"}, the port is pinned to ${PINNED}`);
  }
  const lists = buildLists(freqDir || clone);
  const tmp = mkdtempSync(path.join(tmpdir(), "skim-parity-"));
  for (const d of ["core", "dom"]) mkdirSync(path.join(tmp, d));
  writeFileSync(path.join(tmp, "package.json"), '{"type":"module"}\n');
  const stage = (rel) => {
    let src = readFileSync(path.join(clone, "src", rel), "utf8");
    src = src.replace(/from '(\.[^']*)'/g, (_m, p) => `from '${p}.ts'`);
    src = src.replace("from 'virtual:skimgram-frequency'", "from './freq.ts'");
    if (rel === "core/scorer.ts") {
      const tail = "return { tokens, levels, stats };";
      if (src.split(tail).length !== 2) throw new Error("upstream scorer.ts no longer ends the way the parity patch expects");
      src = src.replace(tail, "return { tokens, levels, stats, debug: { raw, smoothed, seqIdx } };");
    }
    writeFileSync(path.join(tmp, rel), src);
  };
  for (const rel of ["core/tokenizer.ts", "core/ngram.ts", "core/normalize.ts", "core/scorer.ts", "core/builtin.ts", "dom/walker.ts"]) stage(rel);
  writeFileSync(path.join(tmp, "core/freq.ts"), `export const EN_WORDS = ${JSON.stringify(lists.en)};\nexport const CJK_CHARS = ${JSON.stringify(lists.cjk)};\n`);
  globalThis.NodeFilter = { SHOW_TEXT: 4, FILTER_ACCEPT: 1, FILTER_REJECT: 2, FILTER_SKIP: 3 };
  const load = (rel) => import(pathToFileURL(path.join(tmp, rel)).href);
  const [tok, scorer, walker] = await Promise.all([load("core/tokenizer.ts"), load("core/scorer.ts"), load("dom/walker.ts")]);
  return {
    name: "upstream",
    tokenize: tok.tokenize,
    flatten: (strings) => {
      const r = walker.collectText(fakeRoot(strings));
      return { text: r.text, starts: r.runs.map((x) => x.flatStart) };
    },
    analyze(text, o) {
      const r = scorer.analyze(text, o);
      if (r.skipped) return { skipped: true, reason: r.reason };
      return { skipped: false, basis: r.stats.basis, spread: r.stats.spread, levels: r.levels, seqIdx: r.debug.seqIdx, raw: r.debug.raw, smoothed: r.debug.smoothed };
    },
    lists,
  };
}

// ---- one fixture, seen through one engine, in a form both sides share ----
const encodeLevels = (levels) => Array.from(levels, (l) => String.fromCharCode(97 + l + 2)).join("");

function tokenView(adapter, text) {
  const toks = adapter.tokenize(text);
  return { keys: toks.map((t) => t.key), kinds: toks.map((t) => t.kind), starts: toks.map((t) => t.start), ends: toks.map((t) => t.end) };
}

function buildView(adapter, text) {
  const tokens = tokenView(adapter, text);
  const n = tokens.keys.length;
  const cases = {};
  const scores = {};
  const langs = new Set();
  for (const basis of BASES) {
    for (const intensity of INTENSITIES) {
      const r = adapter.analyze(text, { basis, intensity, minTokens: MIN_TOKENS });
      const id = `${basis}/${intensity}`;
      if (r.skipped) { cases[id] = { skipped: true, reason: r.reason }; if (intensity === 50) scores[basis] = { skipped: true }; continue; }
      if (r.lang) langs.add(r.lang);
      cases[id] = { skipped: false, basis: r.basis, levels: encodeLevels(r.levels) };
      if (intensity !== 50) continue;
      const rawTok = new Array(n).fill(NaN);
      const smTok = new Array(n).fill(NaN);
      let k = 0;
      for (let p = 0; p < r.seqIdx.length; p++) {
        if (Number.isNaN(r.raw[p])) continue;
        rawTok[r.seqIdx[p]] = r.raw[p];
        smTok[r.seqIdx[p]] = r.smoothed[k++];
      }
      scores[basis] = { skipped: false, spread: r.spread, rawTok, smTok };
    }
  }
  return { chars: text.length, textSha: sha(text), tokens, cases, scores, langs: [...langs] };
}

const isScored = (kind) => kind === "word" || kind === "cjk";
const round = (x) => Number(x.toPrecision(12));

function toGolden(view) {
  const { tokens } = view;
  for (let i = 0; i < tokens.keys.length; i++) {
    if (tokens.starts[i] !== (i === 0 ? 0 : tokens.ends[i - 1])) throw new Error("tokens do not tile the input, the golden format cannot hold them");
  }
  const scores = {};
  for (const basis of ["surprisal", "gain"]) {
    const s = view.scores[basis];
    scores[basis] = s.skipped ? { skipped: true } : {
      spread: round(s.spread),
      raw: s.rawTok.filter((_v, i) => isScored(tokens.kinds[i])).map(round),
      smoothed: s.smTok.filter((_v, i) => isScored(tokens.kinds[i])).map(round),
    };
  }
  return {
    chars: view.chars, textSha: view.textSha,
    tokens: { kinds: tokens.kinds.map((k) => KIND_CODE[k]).join(""), ends: tokens.ends, keys: tokens.keys },
    cases: view.cases, scores,
  };
}

function fromGolden(g) {
  const kinds = Array.from(g.tokens.kinds, (c) => CODE_KIND[c]);
  const ends = g.tokens.ends;
  const tokens = { keys: g.tokens.keys, kinds, starts: ends.map((_e, i) => (i === 0 ? 0 : ends[i - 1])), ends };
  const n = kinds.length;
  const scores = {};
  for (const basis of ["surprisal", "gain"]) {
    const s = g.scores[basis];
    if (s.skipped) { scores[basis] = { skipped: true }; continue; }
    const rawTok = new Array(n).fill(NaN);
    const smTok = new Array(n).fill(NaN);
    let k = 0;
    for (let i = 0; i < n; i++) if (isScored(kinds[i])) { rawTok[i] = s.raw[k]; smTok[i] = s.smoothed[k]; k++; }
    scores[basis] = { skipped: false, spread: s.spread, rawTok, smTok };
  }
  const auto = g.cases["auto/50"];
  scores.auto = auto.skipped ? { skipped: true } : scores[auto.basis];
  return { chars: g.chars, textSha: g.textSha, tokens, cases: g.cases, scores };
}

// ---- compare ----
function compareViews(ref, got) {
  const flagged = new Set();
  const problems = [];
  let maxDiff = 0;
  const nRef = ref.tokens.keys.length;
  const nGot = got.tokens.keys.length;
  const n = Math.max(nRef, nGot);
  if (nRef !== nGot) problems.push(`token count ${nGot} against ${nRef}`);
  if (ref.textSha !== got.textSha) problems.push("the fixture text differs from the one the golden was made from");
  for (let i = nRef; i < n; i++) flagged.add(i);
  for (let i = 0; i < Math.min(nRef, nGot); i++) {
    for (const f of ["keys", "kinds", "starts", "ends"]) if (ref.tokens[f][i] !== got.tokens[f][i]) flagged.add(i);
  }
  const flagAll = () => { for (let i = 0; i < n; i++) flagged.add(i); };
  for (const id of Object.keys(ref.cases)) {
    const a = ref.cases[id];
    const b = got.cases[id];
    if (!b || a.skipped !== b.skipped || (a.skipped && a.reason !== b.reason)) { problems.push(`${id}: skip decision differs`); flagAll(); continue; }
    if (a.skipped) continue;
    if (a.basis !== b.basis) { problems.push(`${id}: basis ${b.basis} against ${a.basis}`); flagAll(); }
    for (let i = 0; i < Math.min(a.levels.length, b.levels.length); i++) if (a.levels[i] !== b.levels[i]) flagged.add(i);
    if (a.levels.length !== b.levels.length) problems.push(`${id}: level count differs`);
  }
  for (const basis of BASES) {
    const a = ref.scores[basis];
    const b = got.scores[basis];
    if (a.skipped || b.skipped) { if (a.skipped !== b.skipped) { problems.push(`${basis}: scored on one side only`); flagAll(); } continue; }
    if (Math.abs(a.spread - b.spread) > TOLERANCE) { problems.push(`${basis}: spread differs`); flagAll(); }
    for (const field of ["rawTok", "smTok"]) {
      for (let i = 0; i < Math.min(a[field].length, b[field].length); i++) {
        const x = a[field][i];
        const y = b[field][i];
        if (Number.isNaN(x) && Number.isNaN(y)) continue;
        const d = Math.abs(x - y);
        if (Number.isNaN(d) || d > TOLERANCE) flagged.add(i);
        if (!Number.isNaN(d)) maxDiff = Math.max(maxDiff, d);
      }
    }
  }
  return { flagged: flagged.size, problems, maxDiff };
}

// ---- page flattening, including the character cap ----
function capCases(longText) {
  const paragraphs = longText.split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean);
  const over = [];
  for (let size = 0, i = 0; size < 460000; i++) { const p = paragraphs[i % paragraphs.length]; over.push(p); size += p.length + 1; }
  // the cap trips on offset >= 400000: build nodes whose offset lands on 400000 and on 399999
  const edge = (last) => {
    const nodes = Array.from({ length: 399 }, () => "a".repeat(1000));
    nodes.push("b".repeat(last), "tail one", "tail two");
    return nodes;
  };
  return { "under-cap": paragraphs.slice(0, 40), "over-cap": over, "cap-exact-400000": edge(601), "cap-just-under": edge(600) };
}

function buildCap(adapter, longText) {
  const out = {};
  for (const [name, strings] of Object.entries(capCases(longText))) {
    const f = adapter.flatten(strings);
    out[name] = { runs: f.starts.length, length: f.text.length, textSha: sha(f.text), startsSha: sha(f.starts.join(",")) };
  }
  return out;
}

// ---- run ----
const port = loadPort();
const files = readdirSync(FIXTURES).filter((f) => f.endsWith(".txt")).sort();
const longText = readFileSync(path.join(FIXTURES, "en-long.txt"), "utf8");
let ref;
let source;
if (args.upstream) {
  const up = await loadUpstream(path.resolve(args.upstream), args.freqDir ? path.resolve(args.freqDir) : "");
  source = `upstream skimgram ${PINNED}, run live (word lists: most-common-words-by-language ${up.lists.versions.enPkg}, hanzi ${up.lists.versions.zhPkg})`;
  ref = { views: {}, cap: buildCap(up, longText), lists: { en: up.lists.en, cjk: up.lists.cjk } };
  for (const f of files) ref.views[f] = buildView(up, readFileSync(path.join(FIXTURES, f), "utf8"));
  if (args.writeGolden) {
    mkdirSync(GOLDEN, { recursive: true });
    for (const f of files) writeFileSync(path.join(GOLDEN, f.replace(/\.txt$/, ".json")), JSON.stringify(toGolden(ref.views[f])) + "\n");
    writeFileSync(path.join(GOLDEN, "_meta.json"), JSON.stringify({
      upstream: PINNED, tolerance: TOLERANCE, bases: BASES, intensities: INTENSITIES, minTokens: MIN_TOKENS,
      lists: { enSha: sha(ref.lists.en), cjkSha: sha(ref.lists.cjk), enCount: ref.lists.en.split(" ").length, cjkCount: [...ref.lists.cjk].length },
      cap: ref.cap,
    }, null, 1) + "\n");
    console.log(`wrote ${files.length} goldens and _meta.json to ${path.relative(ROOT, GOLDEN)}`);
  }
} else {
  if (!existsSync(path.join(GOLDEN, "_meta.json"))) { console.error("skim-parity: no goldens in tests/fixtures/skim/golden, run with --upstream <clone> --write-golden"); process.exit(2); }
  const meta = JSON.parse(readFileSync(path.join(GOLDEN, "_meta.json"), "utf8"));
  source = `committed goldens from upstream skimgram ${meta.upstream}`;
  ref = { views: {}, cap: meta.cap, listHashes: meta.lists };
  for (const f of files) {
    const g = path.join(GOLDEN, f.replace(/\.txt$/, ".json"));
    if (!existsSync(g)) { console.error(`skim-parity: no golden for ${f}`); process.exit(2); }
    ref.views[f] = fromGolden(JSON.parse(readFileSync(g, "utf8")));
  }
}

let bad = 0;
const rows = [];
for (const f of files) {
  const got = buildView(port, readFileSync(path.join(FIXTURES, f), "utf8"));
  const r = compareViews(ref.views[f], got);
  const langOther = got.langs.includes("other");
  const seq = got.tokens.kinds.filter((k) => k !== "space").length;
  const scored = got.tokens.kinds.filter(isScored).length;
  const skipped = Object.values(got.cases).every((c) => c.skipped);
  if (r.flagged || r.problems.length || langOther) bad++;
  rows.push({ f, n: got.tokens.keys.length, nRef: ref.views[f].tokens.keys.length, seq, scored: skipped ? "skipped" : scored, lang: got.langs.join(",") || "-", r, langOther });
}

console.log(`skim-parity: port against ${source}`);
console.log(`matrix: basis ${BASES.join("/")} x intensity ${INTENSITIES.join("/")}, minTokens ${MIN_TOKENS}, scores equal to ${TOLERANCE}`);
console.log("");
const pad = (s, w) => String(s).padEnd(w);
console.log(`${pad("fixture", 20)}${pad("tokens", 8)}${pad("upstream", 10)}${pad("sequence", 10)}${pad("scored", 9)}${pad("lang", 6)}${pad("mismatch", 10)}max score diff`);
for (const x of rows) {
  console.log(`${pad(x.f.replace(/\.txt$/, ""), 20)}${pad(x.n, 8)}${pad(x.nRef, 10)}${pad(x.seq, 10)}${pad(x.scored, 9)}${pad(x.lang, 6)}${pad(x.r.flagged, 10)}${x.r.maxDiff.toExponential(2)}`);
  for (const p of x.r.problems) console.log(`    ${p}`);
  if (x.langOther) console.log("    the language check sent a parity fixture to the page-only path");
}

console.log("");
let capBad = 0;
const capGot = buildCap(port, longText);
for (const [name, a] of Object.entries(ref.cap)) {
  const b = capGot[name];
  const same = b && a.runs === b.runs && a.length === b.length && a.textSha === b.textSha && a.startsSha === b.startsSha;
  if (!same) capBad++;
  console.log(`flatten ${pad(name, 18)}runs ${pad(b?.runs, 6)}chars ${pad(b?.length, 8)}${same ? "same as upstream" : "DIFFERS from upstream"}`);
}

const enGot = port.lists.en;
const zhGot = port.lists.cjk;
let listBad = 0;
const listSame = (got, refStr, refHash) => (refStr !== undefined ? got === refStr : sha(got) === refHash);
const enOk = listSame(enGot, ref.lists?.en, ref.listHashes?.enSha);
const zhOk = listSame(zhGot, ref.lists?.cjk, ref.listHashes?.cjkSha);
if (!enOk) listBad++;
if (!zhOk) listBad++;
console.log(`word list EN_WORDS ${enGot.split(" ").length} entries ${enOk ? "same as upstream" : "DIFFERS from upstream"}`);
console.log(`word list CJK_CHARS ${[...zhGot].length} entries ${zhOk ? "same as upstream" : "DIFFERS from upstream"}`);

const total = rows.reduce((s, x) => s + x.r.flagged, 0);
console.log("");
console.log(`${total} mismatched tokens over ${rows.length} fixtures, ${capBad} flatten differences, ${listBad} word list differences, ${rows.filter((x) => x.n !== x.nRef).length} token count differences`);
if (bad || capBad || listBad) { console.log("skim-parity: FAIL"); process.exit(1); }
console.log("skim-parity: OK");

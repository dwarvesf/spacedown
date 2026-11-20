#!/usr/bin/env node
// skim-lists: build the two word-frequency lists of the Skim reading mode from public-domain texts.
//
//   node scripts/skim-lists.mjs check-notices       offline: every source in the manifest is credited
//                                                    in THIRD_PARTY_NOTICES.md (skim-parity runs this too)
//   node scripts/skim-lists.mjs build [--cache <dir>] [--write] [--record-hashes]
//                                                    fetch the sources, rebuild both lists, compare them
//                                                    with assets/skim-surprise.html; --write puts them there
//
// Sources: scripts/skim-lists/sources.tsv. English: the 3000 most common words over a set of Project
// Gutenberg public-domain works. Chinese: the 2000 most common Han characters over a set of public-domain
// Chinese works, folded from Traditional to Simplified with the Unihan kSimplifiedVariant field, since the
// texts are Traditional and most Chinese pages today are Simplified.
//
// Ranking: each work counts equally (relative frequency per work, averaged), and an entry must appear in
// at least MIN_SHARE of the works, so a character name or a whaling term cannot ride one book into the
// list. Ties break by code point, so a rebuild from the same files is byte-identical. English keys come
// from the engine's own tokenizer, so a listed word is exactly the key Skim looks up.
//
// The build reads the network (Project Gutenberg, unicode.org); the app and the CLI never run it.
// Each fetched file must match the sha256 in the manifest; --record-hashes fills or replaces them.
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MANIFEST = path.join(ROOT, "scripts/skim-lists/sources.tsv");
const NOTICES = path.join(ROOT, "THIRD_PARTY_NOTICES.md");
const ENGINE = path.join(ROOT, "assets/skim-surprise.html");
const EN_SIZE = 3000;
const CJK_SIZE = 2000;
const MIN_SHARE = { en: 0.4, cjk: 0.5 };
const DIED_BY = 1955;
const PUBLISHED_BY = 1929;
const EN_ALLOWED = /^[a-z0-9'-]+$/;
const GUTENBERG = ["https://gutenberg.pglaf.org/cache/epub/{id}/pg{id}.txt", "https://www.gutenberg.org/cache/epub/{id}/pg{id}.txt"];
const UNIHAN = "https://www.unicode.org/Public/{id}/ucd/Unihan.zip";

const sha = (b) => createHash("sha256").update(b).digest("hex");

export function readManifest() {
  const lines = readFileSync(MANIFEST, "utf8").split("\n").filter((l) => l && !l.startsWith("#"));
  const head = lines.shift().split("\t");
  return lines.map((l) => Object.fromEntries(l.split("\t").map((v, i) => [head[i], v])));
}

// How THIRD_PARTY_NOTICES.md must name a source.
export const citation = (row) => (row.source === "gutenberg" ? `#${row.id}` : `Unihan ${row.id}`);

// The offline provenance check: a list whose source is not credited fails.
export function checkNotices() {
  const notices = readFileSync(NOTICES, "utf8");
  const engine = readFileSync(ENGINE, "utf8");
  const problems = [];
  const rows = readManifest();
  for (const r of rows) {
    const cite = citation(r);
    const re = new RegExp(`${cite.replace(/[.#]/g, (c) => `\\${c}`)}(?![0-9.])`);
    if (!re.test(notices)) problems.push(`THIRD_PARTY_NOTICES.md does not credit ${r.list} source ${cite} (${r.title})`);
    if (r.source === "gutenberg" && !(Number(r.died) <= DIED_BY && Number(r.published) <= PUBLISHED_BY)) {
      problems.push(`${cite} breaks the public-domain rule: died ${r.died}, published ${r.published}`);
    }
  }
  for (const list of ["en", "cjk"]) if (!rows.some((r) => r.list === list)) problems.push(`the manifest has no source for ${list}`);
  if (!notices.includes("scripts/skim-lists/sources.tsv")) problems.push("THIRD_PARTY_NOTICES.md does not name scripts/skim-lists/sources.tsv");
  if (!engine.includes("scripts/skim-lists/sources.tsv")) problems.push("assets/skim-surprise.html does not record its list source");
  return { sources: rows.length, problems };
}

// ---- the build ----
async function fetchOnce(urls, file) {
  if (existsSync(file)) return readFileSync(file);
  for (let attempt = 0; attempt < 3; attempt++) {
    for (const url of urls) {
      try {
        const res = await fetch(url);
        if (!res.ok) continue;
        const buf = Buffer.from(await res.arrayBuffer());
        writeFileSync(file, buf);
        await new Promise((r) => setTimeout(r, 500)); // be gentle with the mirror
        return buf;
      } catch {
        // a dropped connection: try the next mirror, then the next round
      }
    }
  }
  throw new Error(`could not fetch ${urls[0]}`);
}

function gutenbergBody(text, id) {
  const start = text.search(/^\*\*\* ?START OF (THE|THIS) PROJECT GUTENBERG EBOOK.*$/m);
  const end = text.search(/^\*\*\* ?END OF (THE|THIS) PROJECT GUTENBERG EBOOK/m);
  if (start < 0 || end < 0 || end < start) throw new Error(`#${id}: no Project Gutenberg START/END markers`);
  return text.slice(text.indexOf("\n", start) + 1, end);
}

function engineTokenizer() {
  const html = readFileSync(ENGINE, "utf8");
  const ctx = { window: {} };
  vm.createContext(ctx);
  vm.runInContext(html.slice(html.indexOf("<script>") + 8, html.lastIndexOf("</script>")), ctx);
  return ctx.window.sdSurprise.tokenize;
}

function countEnglish(tokenize, body) {
  // Counting only: curly apostrophes as straight ones, and a dash written as two hyphens splits words.
  const text = body.replace(/[‘’]/g, "'").replace(/-{2,}/g, " ");
  const counts = new Map();
  let total = 0;
  for (const t of tokenize(text)) {
    if (t.kind !== "word") continue;
    const key = t.key.replace(/^['-]+/, "");
    if (!key || key.length > 20 || !EN_ALLOWED.test(key) || !/[a-z]/.test(key)) continue;
    counts.set(key, (counts.get(key) || 0) + 1);
    total++;
  }
  return { counts, total };
}

// The Han ranges the engine's tokenizer scores, BMP only (the engine indexes CJK_CHARS by UTF-16 unit).
const isHan = (cp) => (cp >= 0x3400 && cp <= 0x4dbf) || (cp >= 0x4e00 && cp <= 0x9fff) || (cp >= 0xf900 && cp <= 0xfaff);

function simplifiedMap(variantsText) {
  const map = new Map();
  for (const line of variantsText.split("\n")) {
    const m = line.match(/^U\+([0-9A-F]+)\tkSimplifiedVariant\t(.+)$/);
    if (!m) continue;
    const from = String.fromCodePoint(parseInt(m[1], 16));
    const to = m[2].trim().split(/\s+/).map((u) => String.fromCodePoint(parseInt(u.slice(2), 16)));
    // One-to-many (著 lists 着 and 著, 裡 lists 裡 and 里): the first variant that is not the character
    // itself, so the list holds the Simplified form a modern page uses most.
    const pick = to.find((c) => c !== from) ?? from;
    if (pick !== from && pick.length === 1 && isHan(pick.codePointAt(0))) map.set(from, pick);
  }
  return map;
}

function countChinese(simp, body) {
  const counts = new Map();
  let total = 0;
  for (const raw of body.normalize("NFC")) {
    if (!isHan(raw.codePointAt(0))) continue;
    const ch = simp.get(raw) || raw;
    counts.set(ch, (counts.get(ch) || 0) + 1);
    total++;
  }
  return { counts, total };
}

function rank(perWork, size, minShare) {
  const n = perWork.length, need = Math.ceil(minShare * n);
  const score = new Map(), df = new Map();
  for (const { counts, total } of perWork) {
    for (const [k, c] of counts) {
      score.set(k, (score.get(k) || 0) + c / total / n);
      df.set(k, (df.get(k) || 0) + 1);
    }
  }
  const keys = [...score.keys()].filter((k) => df.get(k) >= need);
  keys.sort((a, b) => score.get(b) - score.get(a) || (a < b ? -1 : a > b ? 1 : 0));
  if (keys.length < size) throw new Error(`only ${keys.length} entries pass the ${need}-work floor, ${size} needed`);
  return keys.slice(0, size);
}

export async function buildLists({ cache = path.join(tmpdir(), "spacedown-skim-lists"), recordHashes = false, log = () => {} } = {}) {
  mkdirSync(cache, { recursive: true });
  const rows = readManifest();
  const drift = [];
  const load = async (row, urls, name) => {
    const buf = await fetchOnce(urls, path.join(cache, name));
    const got = sha(buf);
    if (row.sha256 && row.sha256 !== got) drift.push(`${citation(row)}: sha256 ${got} against the manifest's ${row.sha256}`);
    row.sha256 = got;
    return buf;
  };
  const unihanRow = rows.find((r) => r.source === "unihan");
  const zip = path.join(cache, `Unihan-${unihanRow.id}.zip`);
  await load(unihanRow, [UNIHAN.replace("{id}", unihanRow.id)], path.basename(zip));
  const unz = spawnSync("unzip", ["-p", zip, "Unihan_Variants.txt"], { encoding: "utf8", maxBuffer: 64 << 20 });
  if (unz.status !== 0) throw new Error(`unzip failed on ${zip}: ${unz.stderr}`);
  const simp = simplifiedMap(unz.stdout);

  const tokenize = engineTokenizer();
  const en = [], cjk = [];
  for (const row of rows.filter((r) => r.source === "gutenberg")) {
    const buf = await load(row, GUTENBERG.map((u) => u.replaceAll("{id}", row.id)), `pg${row.id}.txt`);
    const text = buf.toString("utf8");
    const bad = (text.match(/�/g) || []).length;
    if (bad > 10) throw new Error(`#${row.id}: ${bad} undecodable characters, not UTF-8`);
    const body = gutenbergBody(text, row.id);
    const counted = row.list === "en" ? countEnglish(tokenize, body) : countChinese(simp, body);
    log(`  #${row.id} ${row.list} ${counted.total} tokens  ${row.title}`);
    (row.list === "en" ? en : cjk).push(counted);
  }
  if (drift.length && !recordHashes) throw new Error(`sources changed since the manifest was written:\n  ${drift.join("\n  ")}\nre-run with --record-hashes, then review the list diff`);
  if (recordHashes) writeManifestHashes(rows);
  const chars = rank(cjk, CJK_SIZE, MIN_SHARE.cjk);
  const unfolded = chars.filter((c) => simp.has(c));
  if (unfolded.length) throw new Error(`Traditional characters left in the Chinese list: ${unfolded.join("")}`);
  return {
    en: rank(en, EN_SIZE, MIN_SHARE.en).join(" "),
    cjk: chars.join(""),
    works: { en: en.length, cjk: cjk.length },
  };
}

function writeManifestHashes(rows) {
  const lines = readFileSync(MANIFEST, "utf8").split("\n");
  const byId = new Map(rows.map((r) => [`${r.source}:${r.id}`, r.sha256]));
  const out = lines.map((l) => {
    if (!l || l.startsWith("#") || l.startsWith("list\t")) return l;
    const f = l.split("\t");
    f[7] = byId.get(`${f[1]}:${f[2]}`) || f[7];
    return f.join("\t");
  });
  writeFileSync(MANIFEST, out.join("\n"));
}

const escapeCjk = (s) => [...s].map((c) => `\\u${c.codePointAt(0).toString(16).padStart(4, "0")}`).join("");

export function engineLists() {
  const html = readFileSync(ENGINE, "utf8");
  const list = (name) => JSON.parse(html.match(new RegExp(`var ${name} = ("[^"]*");`))[1]);
  return { en: list("EN_WORDS"), cjk: list("CJK_CHARS") };
}

function writeEngine(lists) {
  let html = readFileSync(ENGINE, "utf8");
  const swap = (name, literal) => {
    const re = new RegExp(`var ${name} = "[^"]*";`);
    if (!re.test(html)) throw new Error(`no ${name} line in ${ENGINE}`);
    html = html.replace(re, () => `var ${name} = "${literal}";`);
  };
  swap("EN_WORDS", lists.en);
  swap("CJK_CHARS", escapeCjk(lists.cjk));
  writeFileSync(ENGINE, html);
}

async function main(argv) {
  const cmd = argv[0];
  if (cmd === "check-notices") {
    const r = checkNotices();
    for (const p of r.problems) console.log(`  ${p}`);
    console.log(r.problems.length ? `skim-lists: FAIL, ${r.problems.length} provenance problems` : `skim-lists: OK, ${r.sources} sources credited`);
    process.exit(r.problems.length ? 1 : 0);
  }
  if (cmd !== "build") {
    console.log("Usage: skim-lists.mjs check-notices | build [--cache <dir>] [--write] [--record-hashes]");
    process.exit(cmd === "-h" || cmd === "--help" ? 0 : 2);
  }
  const opts = { log: console.log };
  let write = false;
  for (let i = 1; i < argv.length; i++) {
    if (argv[i] === "--cache") opts.cache = path.resolve(argv[++i]);
    else if (argv[i] === "--write") write = true;
    else if (argv[i] === "--record-hashes") opts.recordHashes = true;
    else { console.error(`unknown option ${argv[i]}`); process.exit(2); }
  }
  const lists = await buildLists(opts);
  const have = engineLists();
  console.log(`EN_WORDS  ${lists.en.split(" ").length} words from ${lists.works.en} works, sha256 ${sha(lists.en)}`);
  console.log(`CJK_CHARS ${[...lists.cjk].length} characters from ${lists.works.cjk} works, sha256 ${sha(lists.cjk)}`);
  if (write) { writeEngine(lists); console.log(`wrote both lists to ${path.relative(ROOT, ENGINE)}`); return; }
  const same = have.en === lists.en && have.cjk === lists.cjk;
  console.log(same ? "skim-lists: the engine's lists equal the rebuild" : "skim-lists: the engine's lists DIFFER from the rebuild (run with --write)");
  process.exit(same ? 0 : 1);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch((e) => { console.error(`skim-lists: ${e.message}`); process.exit(2); });
}

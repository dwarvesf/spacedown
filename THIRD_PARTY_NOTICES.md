# Third-party notices

Spacedown and the spacedown CLI bundle or reference the third-party works below. Each keeps its own license. The upstream projects hold the full license texts.

## Bundled code

| Component | Version | Where it lives | License | Upstream |
|---|---|---|---|---|
| marked | 12.0.2 | `integrations/safari/quick-look/Resources/marked.min.js` | MIT, Copyright (c) 2011-2024 Christopher Jeffrey and the MarkedJS contributors | https://github.com/markedjs/marked |
| KaTeX | 0.16.11 | `integrations/safari/quick-look/Resources/katex.min.js`, `katex.min.css` | MIT, Copyright (c) 2013-2020 Khan Academy and other contributors | https://github.com/KaTeX/KaTeX |
| highlight.js, with its `github` and `github-dark` themes | 11.11.1 | `integrations/safari/quick-look/Resources/highlight.min.js`, `hljs-theme.css` | BSD-3-Clause, Copyright (c) 2006 Ivan Sagalaev and contributors | https://github.com/highlightjs/highlight.js |
| VS Code markdown preview stylesheet (`markdown.css`) | see `assets/REFRESH.md` | part (4) of `assets/vscode-preview-head.html`, copied into the Quick Look bundle at build time | MIT, Copyright (c) Microsoft Corporation | https://github.com/microsoft/vscode |
| skimgram scoring core (tokenizer, n-gram model, scorer, rank normalizer), ported to plain JS; the extension and its DOM code are not included | 0.1.1 | `assets/skim-surprise.html`, the engine behind the Skim (surprise) reading mode | MIT, Copyright (c) 2026 AwesomeDog | https://github.com/awesomedog/skimgram |

## Word-frequency data (bundled)

`assets/skim-surprise.html` carries two rank-ordered word lists, the same data skimgram builds in. Only the ordering is kept (a rank becomes a probability), no counts and no text from the sources.

| Data | Where it lives | Taken from | License of the package |
|---|---|---|---|
| The 3000 most common English words | `EN_WORDS` in `assets/skim-surprise.html` | `most-common-words-by-language` 3.0.14, whose English list is first20hours/google-10000-english | MIT, https://github.com/oprogramador/most-common-words-by-language |
| The 2000 most common Chinese characters | `CJK_CHARS` in `assets/skim-surprise.html` | `hanzi` 3.2.0, Jun Da's character frequency list (see http://lingua.mtsu.edu/chinese-computing/copyright.html) | MIT, https://github.com/nieldlr/Hanzi |

## Runtime dependencies (not bundled)

| Component | Role | License | Upstream |
|---|---|---|---|
| pandoc | Markdown to HTML conversion in the CLI | GPL-2.0-or-later | https://github.com/jgm/pandoc |
| KaTeX (CDN copy) | Math in CLI output pages, loaded by pandoc from a CDN | MIT | https://github.com/KaTeX/KaTeX |
| entr | Optional file watching for `--watch` | ISC | https://github.com/eradman/entr |

The spacedown CLI runs pandoc and entr as separate programs and includes none of their code.

## Fonts (bundled)

| Font | Where it lives | License | Upstream |
|---|---|---|---|
| iA Writer Quattro V, iA Writer Mono V (upright and italic) | `assets/fonts/ia/*.ttf`, license text in `assets/fonts/ia/LICENSE.md` | SIL Open Font License 1.1, Copyright (c) 2018 Information Architects Inc. with Reserved Font Name "iA Writer"; based on IBM Plex, Copyright (c) 2017 IBM Corp. | https://github.com/iaolo/iA-Fonts |

The four files are embedded as base64 data URIs into the Quick Look reading skin at build time (`scripts/build-ql-skin`), because the sandboxed Quick Look webview cannot load installed fonts. The browser themes `ia` and `paper` name the fonts by family and do not embed them. `spacedown docx` sets documents in IBM Plex Sans and IBM Plex Mono (SIL OFL 1.1, IBM Corp.) by name and ships no Plex files.

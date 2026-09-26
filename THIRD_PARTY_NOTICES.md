# Third-party notices

Spacedown and the spacedown CLI bundle or reference the third-party works below. Each keeps its own license. The upstream projects hold the full license texts.

## Bundled code

| Component | Version | Where it lives | License | Upstream |
|---|---|---|---|---|
| marked | 12.0.2 | `integrations/safari/quick-look/Resources/marked.min.js` | MIT, Copyright (c) 2011-2024 Christopher Jeffrey and the MarkedJS contributors | https://github.com/markedjs/marked |
| KaTeX | 0.16.11 | `integrations/safari/quick-look/Resources/katex.min.js`, `katex.min.css` | MIT, Copyright (c) 2013-2020 Khan Academy and other contributors | https://github.com/KaTeX/KaTeX |
| highlight.js, with its `github` and `github-dark` themes | 11.11.1 | `integrations/safari/quick-look/Resources/highlight.min.js`, `hljs-theme.css` | BSD-3-Clause, Copyright (c) 2006 Ivan Sagalaev and contributors | https://github.com/highlightjs/highlight.js |
| VS Code markdown preview stylesheet (`markdown.css`) | see `assets/REFRESH.md` | part (4) of `assets/vscode-preview-head.html`, copied into the Quick Look bundle at build time | MIT, Copyright (c) Microsoft Corporation | https://github.com/microsoft/vscode |

## Runtime dependencies (not bundled)

| Component | Role | License | Upstream |
|---|---|---|---|
| pandoc | Markdown to HTML conversion in the CLI | GPL-2.0-or-later | https://github.com/jgm/pandoc |
| KaTeX (CDN copy) | Math in CLI output pages, loaded by pandoc from a CDN | MIT | https://github.com/KaTeX/KaTeX |
| entr | Optional file watching for `--watch` | ISC | https://github.com/eradman/entr |

The spacedown CLI runs pandoc and entr as separate programs and includes none of their code.

## Fonts (referenced, not bundled)

| Font | License | Upstream |
|---|---|---|
| iA Writer Quattro, iA Writer Mono | SIL Open Font License 1.1 | https://github.com/iaolo/iA-Fonts |

Fonts by Information Architects. The `paper` theme and the Quick Look skin name these typefaces in CSS font stacks. spacedown ships no font files and falls back to system fonts when the iA Writer fonts are not installed.

# Third-party notices

Spacedown and the spacedown CLI bundle or reference the third-party works below. Each keeps its own license. The upstream projects hold the full license texts. Spacedown's own code is AGPL-3.0-only ([NOTICE](NOTICE)); the licenses of the bundled code, data and fonts below (MIT, BSD-3-Clause, SIL OFL 1.1, public domain) are compatible with it.

## Bundled code

| Component | Version | Where it lives | License | Upstream |
|---|---|---|---|---|
| marked | 12.0.2 | `integrations/safari/quick-look/Resources/marked.min.js` | MIT, Copyright (c) 2011-2024 Christopher Jeffrey and the MarkedJS contributors | https://github.com/markedjs/marked |
| KaTeX (script, stylesheet and woff2 fonts, one version) | 0.19.0 | `integrations/safari/quick-look/Resources/katex.min.js`, `katex.min.css`; fonts in `assets/katex/fonts/*.woff2`, license text in `assets/katex/LICENSE`. `scripts/build-ql-katex` embeds the fonts in the stylesheet the app ships; the panel and the CLI both read that one copy | MIT, Copyright (c) 2013-2020 Khan Academy and other contributors | https://github.com/KaTeX/KaTeX |
| highlight.js, with its `github` and `github-dark` themes | 11.11.1 | `integrations/safari/quick-look/Resources/highlight.min.js`, `hljs-theme.css` | BSD-3-Clause, Copyright (c) 2006 Ivan Sagalaev and contributors | https://github.com/highlightjs/highlight.js |
| VS Code markdown preview stylesheet (`markdown.css`) | see `assets/REFRESH.md` | part (4) of `assets/vscode-preview-head.html`, copied into the Quick Look bundle at build time | MIT, Copyright (c) Microsoft Corporation | https://github.com/microsoft/vscode |
| skimgram scoring core (tokenizer, n-gram model, scorer, rank normalizer), ported to plain JS; the extension and its DOM code are not included | 0.1.1, commit 4ebb78a | `assets/skim-surprise.html`, the engine behind the Skim reading mode | MIT, Copyright (c) 2026 AwesomeDog | https://github.com/awesomedog/skimgram |

## Word-frequency data (bundled)

`assets/skim-surprise.html` carries two rank-ordered lists that Skim uses as its prior. Only the ordering is kept (a rank becomes a probability): no counts and no text from the sources. Both lists are derived by `scripts/skim-lists.mjs` from the sources named in `scripts/skim-lists/sources.tsv`, which also records, per source, the evidence for its public-domain status; `assets/REFRESH.md` has the build command.

| Data | Where it lives | Derived from | License |
|---|---|---|---|
| The 3000 most common English words | `EN_WORDS` in `assets/skim-surprise.html` | Project Gutenberg plain-text editions of public-domain English works (weight 0.7), and the Markdown documentation of US federal government repositories (weight 0.3), both listed below | Works: public domain, every contributor died in 1955 or earlier and every work was published in 1929 or earlier (a Library of Congress record or the transcribed title page, cited in the manifest). Repositories: public domain in the US (17 U.S.C. 105) and dedicated worldwide under CC0 1.0 |
| The 2000 most common Chinese characters (Simplified) | `CJK_CHARS` in `assets/skim-surprise.html` | Project Gutenberg plain-text editions of public-domain Chinese works, listed below, folded from Traditional to Simplified with the `kSimplifiedVariant` field of Unihan 16.0.0 | Works: public domain, same rule. Unihan: Unicode License V3 (below), used at build time only |

English works (Project Gutenberg ebook numbers): #1342 Pride and Prejudice (Jane Austen); #158 Emma (Jane Austen); #84 Frankenstein (Mary Shelley); #2701 Moby Dick (Herman Melville); #1661 The Adventures of Sherlock Holmes (Arthur Conan Doyle); #2852 The Hound of the Baskervilles (Arthur Conan Doyle); #2097 The Sign of the Four (Arthur Conan Doyle); #98 A Tale of Two Cities (Charles Dickens); #1400 Great Expectations (Charles Dickens); #730 Oliver Twist (Charles Dickens); #46 A Christmas Carol (Charles Dickens); #74 The Adventures of Tom Sawyer (Mark Twain); #76 Adventures of Huckleberry Finn (Mark Twain); #3176 The Innocents Abroad (Mark Twain); #345 Dracula (Bram Stoker); #174 The Picture of Dorian Gray (Oscar Wilde); #1260 Jane Eyre (Charlotte Bronte); #768 Wuthering Heights (Emily Bronte); #145 Middlemarch (George Eliot); #35 The Time Machine (H. G. Wells); #36 The War of the Worlds (H. G. Wells); #5230 The Invisible Man (H. G. Wells); #215 The Call of the Wild (Jack London); #219 Heart of Darkness (Joseph Conrad); #2814 Dubliners (James Joyce); #4217 A Portrait of the Artist as a Young Man (James Joyce); #160 The Awakening, and Selected Short Stories (Kate Chopin); #541 The Age of Innocence (Edith Wharton); #4517 Ethan Frome (Edith Wharton); #120 Treasure Island (Robert Louis Stevenson); #43 The Strange Case of Dr. Jekyll and Mr. Hyde (Robert Louis Stevenson); #514 Little Women (Louisa May Alcott); #829 Gulliver's Travels (Jonathan Swift); #55 The Wonderful Wizard of Oz (L. Frank Baum); #16 Peter Pan (J. M. Barrie); #113 The Secret Garden (Frances Hodgson Burnett); #45 Anne of Green Gables (L. M. Montgomery); #236 The Jungle Book (Rudyard Kipling); #932 The Fall of the House of Usher (Edgar Allan Poe); #10007 Carmilla (Joseph Sheridan Le Fanu); #2166 King Solomon's Mines (H. Rider Haggard); #1695 The Man Who Was Thursday (G. K. Chesterton); #8492 The King in Yellow (Robert W. Chambers); #201 Flatland (Edwin Abbott Abbott); #1228 On the Origin of Species (Charles Darwin); #205 Walden, and On the Duty of Civil Disobedience (Henry David Thoreau); #23 Narrative of the Life of Frederick Douglass (Frederick Douglass); #2376 Up from Slavery (Booker T. Washington); #2044 The Education of Henry Adams (Henry Adams); #37134 The Elements of Style (William Strunk); #15776 The Economic Consequences of the Peace (John Maynard Keynes); #833 The Theory of the Leisure Class (Thorstein Veblen); #621 The Varieties of Religious Experience (William James); #5116 Pragmatism (William James); #6435 The Principles of Scientific Management (Frederick Winslow Taylor); #1404 The Federalist Papers (Alexander Hamilton, John Jay, James Madison); #815 Democracy in America, Volume 1 (Alexis de Tocqueville).

Chinese works (Project Gutenberg ebook numbers): #24264 紅樓夢 (Dream of the Red Chamber) (Cao Xueqin); #23863 水滸傳 (Water Margin) (Shi Nai'an); #23962 西遊記 (Journey to the West) (Wu Cheng'en); #24032 儒林外史 (The Scholars) (Wu Jingzi); #23950 三國志演義 (Romance of the Three Kingdoms) (Luo Guanzhong); #23850 老殘遊記 (The Travels of Lao Can) (Liu E); #24138 官場現形記 (Officialdom Unmasked) (Li Boyuan); #27166 吶喊 (Call to Arms) (Lu Xun); #24042 徬徨 (Wandering) (Lu Xun); #25271 朝花夕拾 (Dawn Blossoms Plucked at Dusk) (Lu Xun); #27636 沉沦 (Sinking) (Yu Dafu).

The Project Gutenberg editions are read only to count words. No Project Gutenberg text, header or trademark is distributed.

Technical repositories (Markdown files only, at the pinned revision; license, contributing, security and changelog files are skipped):

| Repository | What it is | Author | Revision |
|---|---|---|---|
| `18F/guides` | 18F guides (content, accessibility, engineering, product and methods guides) | 18F, U.S. General Services Administration | `debc24b34f23` |
| `uswds/uswds-site` | U.S. Web Design System documentation site | U.S. Web Design System team, U.S. General Services Administration | `af13d80f071c` |
| `GSA-TTS/identity-dev-docs` | Login.gov developer documentation | Technology Transformation Services, U.S. General Services Administration | `f696cc7db097` |
| `GSA/api-standards` | GSA API standards | U.S. General Services Administration | `12629c3d1fc1` |
| `18F/frontend` | 18F front-end guide | 18F, U.S. General Services Administration | `24c28da4281e` |
| `18F/automated-testing-playbook` | 18F automated testing playbook | 18F, U.S. General Services Administration | `b4dad85252a8` |
| `CMSgov/beneficiary-fhir-data` | Beneficiary FHIR Data Server (Blue Button) documentation | Centers for Medicare and Medicaid Services, U.S. Department of Health and Human Services | `ffc6c4d58b0f` |

The GSA repositories state in `LICENSE.md`: "As a work of the United States Government, this project is in the public domain within the United States. Additionally, we waive copyright and related rights in the work worldwide through the CC0 1.0 Universal public domain dedication." (`18F/guides` words the first sentence "As a work of the United States government, this project is in the public domain within the United States of America.") The CMS repository states in `README.md`: "This project is in the public domain within the United States, and copyright and related rights in the work worldwide are waived through the CC0 1.0 Universal public domain dedication as indicated in LICENSE." The documentation is read only to count words; none of it is distributed.

Unihan 16.0.0 (https://www.unicode.org/Public/16.0.0/ucd/Unihan.zip) is distributed under the Unicode License V3:

> Copyright © 1991-2026 Unicode, Inc.
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of data files and any associated documentation (the "Data Files") or software and any associated documentation (the "Software") to deal in the Data Files or Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, and/or sell copies of the Data Files or Software, and to permit persons to whom the Data Files or Software are furnished to do so, provided that either (a) this copyright and permission notice appear with all copies of the Data Files or Software, or (b) this copyright and permission notice appear in associated Documentation.
>
> THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF THIRD PARTY RIGHTS.
>
> IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES, OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA FILES OR SOFTWARE.
>
> Except as contained in this notice, the name of a copyright holder shall not be used in advertising or otherwise to promote the sale, use or other dealings in these Data Files or Software without prior written authorization of the copyright holder.

`node scripts/skim-parity.mjs` (part of `bash tests/smoke.sh`) fails when a source in the manifest is not credited here or has no evidence recorded there.

## Runtime dependencies (not bundled)

| Component | Role | License | Upstream |
|---|---|---|---|
| pandoc | Optional, `.docx` export in the CLI (`spacedown docx`); HTML needs no pandoc | GPL-2.0-or-later | https://github.com/jgm/pandoc |
| entr | Optional file watching for `--watch` | ISC | https://github.com/eradman/entr |

The spacedown CLI runs pandoc and entr as separate programs and includes none of their code.

## Fonts (bundled)

| Font | Where it lives | License | Upstream |
|---|---|---|---|
| iA Writer Quattro V, iA Writer Mono V (upright and italic) | `assets/fonts/ia/*.ttf`, license text in `assets/fonts/ia/LICENSE.md` | SIL Open Font License 1.1, Copyright (c) 2018 Information Architects Inc. with Reserved Font Name "iA Writer"; based on IBM Plex, Copyright (c) 2017 IBM Corp. | https://github.com/iaolo/iA-Fonts |

The four files are embedded as base64 data URIs into the Quick Look reading skin at build time (`scripts/build-ql-skin`), because the sandboxed Quick Look webview cannot load installed fonts. The browser themes `ia` and `paper` name the fonts by family and do not embed them. `spacedown docx` sets documents in IBM Plex Sans and IBM Plex Mono (SIL OFL 1.1, IBM Corp.) by name and ships no Plex files.

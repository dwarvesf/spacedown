# Changelog

All notable changes to Spacedown are listed here, in the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. Each section lists what users see first and what developers see last. Numbers in parentheses are pull requests.

## License

Spacedown is AGPL-3.0-only after v1.1.0. Version 1.1.0 and every release before it stay under the MIT license. See [NOTICE](NOTICE).

## [Unreleased]

## [1.2.0] - 2026-11-21

### Added

- Spacedown runs on Intel Macs too: the app and its Quick Look extension are universal (arm64 and x86_64) (#100).
- Writing X-ray lens in the Quick Look panel (#68).
- Present mode: slides from H2 headings and `---` breaks (#65).
- Read menu with Skim, Bionic, BeeLine and RSVP reading modes (#34, #37, #38, #40).
- Native Settings window and a first-launch onboarding that checks a Quick Look sample (#69, #70).
- The `spacedown` command-line tool is bundled inside Spacedown.app (#29).
- `spacedown docx` writes a Word file from Markdown (#27).
- `spacedown mcp`, a free stdio MCP server that lets an agent render, screenshot and lint Markdown (#76).
- `spacedown --shot` screenshots the rendered page headless, `--offline` blocks DNS for the shot, and `--host` shows a document on another machine (#50, #59, #60).
- `--shot` warns when KaTeX draws a formula in red and names the widest cell of a wide table (#56, #57).
- Static landing page and privacy page (#67).

### Changed

- macOS 13 is the minimum for the whole app; the Quick Look extension asked for macOS 12 before (#100).
- The Skim word lists are built from public-domain texts (#95).
- The code is AGPL-3.0-only from this version. The Spacedown name and icon are outside the license; see [TRADEMARKS.md](TRADEMARKS.md) (#84, #85, #86).
- Contributions are accepted under the MIT license (inbound) and ship under the AGPL (outbound) (#86).
- The command-line tool renders HTML through the same core as Quick Look, so the two match (#71).
- A smaller download: stripped binaries, one KaTeX copy and a trimmed highlight.js (#66, #74).
- Math renders offline and numbers labeled equations; KaTeX is pinned to 0.19.0 (#51, #58).
- Reading layout: a 50rem reading column, phone gutters, tables that fit or scroll in their own box, and soft table hairlines (#23, #26, #30, #31, #32, #36, #42).
- The Skim mode defaults to Dim only (#41).
- The Console Labs brand replaces the old one across the docs, the site and the app (#83).
- The privacy policy matches the command-line tool (#82).

### Fixed

- Indented code blocks, and code spans that run over a line break, stay literal, never math or a callout (#100).
- The welcome window fits on a small screen (#99).
- Code spans and fences stay literal, never math or a callout (#72).
- Box-drawing diagrams stay aligned in the panel, with a fallback font so lines join (#28, #58, #79).
- A table right under a line of text renders as a table, in HTML and in Word (#47, #48).
- Wrapped bullet lines hang under the text, and a blank table row keeps a full line of height (#25, #49).
- Reading modes never wrap math before KaTeX runs (#52).
- A declared SVG width is kept instead of stretched (#53).
- A numbered `<details>` summary stays on one line (#54).
- TSV and CSV fences render as tables (#55).
- `spacedown open` prefers Helium when it is installed (#44).

### For developers

- Release 1 contract: the plug-in registry, the settings store and the test sections (#62).
- The repo is ready for outside developers: `AGENTS.md`, `CONTRIBUTING.md`, issue and PR templates, proof files (#81).
- ADR 0001 records the AGPL decision, the paid-feature gate and the license ask (#87).
- Security policy, code of conduct and this changelog (#88); a PR shape check, a CI summary and code owners for every script (#89, #94).
- The agent harness works for any contributor, with a guard that keeps frozen files on `contract/` branches (#98).
- `CONFIG=Debug integrations/build-safari.sh` makes a test build whose ids, App Group and helper carry `.dev`, so it installs beside a release (#100).
- The size budget is 2.8 MB for the app and 1.5 MB for the dmg, measured on the universal build; the unused `Icon.png` stub is gone (#100).
- Release notes come from this file (`scripts/release-notes.sh`), and `scripts/release.sh` keeps older releases unless `PRUNE_OLD_RELEASES=1` (#RP).
- Size budget test, and a build that refuses a release with stale extension versions (#45, #66, #74).
- The build can notarize with an App Store Connect API key (#43).
- A deterministic smoke baseline, `--only` subset runs and a `layout-check` script (#35, #61, #64).
- Removed the pandoc-era filters and unused KaTeX copies, and dropped the pandoc-for-HTML claims from the docs (#73, #75).

## [1.1.0] - 2026-10-16

### Added

- Quick Look preview for Markdown on macOS 13 and later. Open the `.dmg` (or unzip the `.zip`), drag Spacedown to Applications, open it once, then press space on any `.md` file in Finder.

This release and every release before it are MIT licensed.

[Unreleased]: https://github.com/consolelabs/spacedown/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/consolelabs/spacedown/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/consolelabs/spacedown/releases/tag/v1.1.0

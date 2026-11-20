---
name: panel-runs-no-scripts
description: The Quick Look preview is an HTML string rendered with JavaScript off, so page-time hooks never run in the Finder panel; build the feature at render time.
---

The Quick Look extension is data-based. It hands Quick Look an HTML string, Quick Look renders it with JavaScript off, and the page CSP blocks scripts too. Render-time hooks (`transform`, `css`, `controls`, `toolbar`) run everywhere. Page-time hooks (`init`, `key`, `print`, `reset`) run only in a page that calls `SD.boot`, such as the CLI page.

**Why:** a feature that works in node and in the CLI page can be dead in the Finder panel, and the unit tests stay green.

**How to apply:** for the panel, mark the text at render time and toggle with a CSS checkbox, not `:has()` (the deployment target is macOS 12.0). Test the real panel, in a VM or a clean macOS user, before you claim a panel feature works. Source: `docs/contract-r1.md`, "Read this first".

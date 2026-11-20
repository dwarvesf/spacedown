---
name: build-safari-installs-by-default
description: integrations/build-safari.sh installs and registers the app on the current Mac unless NO_INSTALL=1; use the flag, and check the live panel in a VM or a clean user.
---

`integrations/build-safari.sh` without `NO_INSTALL=1` copies `Spacedown.app` into `~/Applications`, registers the Quick Look extension and opens the app.

**Why:** that changes the Quick Look setup of the account you work in, and a later preview on that Mac may come from your build, not the one you meant to test. A broken test build would then show up in everyday use.

**How to apply:** for a compile and signature check, run `NO_INSTALL=1 integrations/build-safari.sh`. For the live panel, install and press space in a VM or a clean macOS user, never on a daily-use Mac. The `ui-change` skill has the steps.

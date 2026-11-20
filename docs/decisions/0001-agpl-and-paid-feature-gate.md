# 0001: AGPL, the paid-feature gate and the license ask

- **Status**: Accepted
- **Date**: 2026-11-21

## Context

Spacedown was MIT licensed up to and including v1.1.0. From the commit that added [NOTICE](../../NOTICE) it is AGPL-3.0-only, with the name and icon kept out of the license under AGPL section 7(e) ([TRADEMARKS.md](../../TRADEMARKS.md)). The maintainer decided to follow the model TablePro uses ([TableProApp/TablePro](https://github.com/TableProApp/TablePro), its ADR 0023): the code stays public, paid features live in the same repo, a signed license unlocks them, and the app asks politely for a license after 30 days of use.

Spacedown has three surfaces that could offer a paid feature:

```
 Spacedown.app (host app, Settings window) ──┐
 SpacedownQL.appex (Quick Look panel) ───────┼──► one gate: gate(feature) ──► license file (Ed25519, offline)
 spacedown CLI and `spacedown mcp` ──────────┘
```

The Quick Look panel is special. It is sandboxed, it hands Quick Look an HTML string, and that HTML runs no scripts ([contract-r1.md](../contract-r1.md)). Most use of Spacedown happens there, but nothing in the panel can open a window, a dialog or a store page.

Nothing is gated yet, and no paid feature exists in the code at this ADR's date.

## Decision

- **One gate.** A single function answers for a feature code: the feature is available, or here is what to show instead. The host app, the Quick Look extension and the CLI (and so the MCP server, which runs through the CLI) all ask it. Nothing reads the license file by hand to decide access. A paid feature calls the gate before it runs and shows the gate's notice when the answer is no.
- **License format v1: an offline license file signed with Ed25519.** The app and the CLI embed the public key and verify the signature offline. The private key never enters this repo. No accounts and no license server in v1: the app makes no network call to check a license. The file names at least a license id, the product, what it unlocks, its issue date and an optional end date; the exact fields are the implementation PR's. A later server-backed Pro feature (share links or sync, for example) may add an account; that gets its own ADR and does not change v1 files.
- **What a gated feature shows.**

  | State | What the user sees | Actions |
  |---|---|---|
  | No license | "{feature} is a Pro feature" and one line on what it does | Buy a license, Add a license file |
  | Invalid license (bad signature, damaged file, another product) | "This license file is not valid" and the reason | Add a license file, Contact support |
  | Expired license (past its end date) | "Your license ended on {date}" | Renew, Add a license file |
  | The check could not run (file unreadable, shared store not reachable, the verifier failed) | "Could not check your license" and the error | Try again |

  A check that cannot run never asks a paying user to buy: that row has no Buy button and no Pro pitch. In the app a gated command shows the notice in an alert; a gated pane shows it in place. In the Quick Look panel the notice is plain text in place of the feature that says to open Spacedown, because the panel runs no scripts and cannot act. The CLI prints the notice on stderr and exits non-zero.
- **The license ask**, adapted from TablePro's to a Quick Look app.
  - Spacedown counts the distinct local days it is used: a day counts when a Quick Look preview renders or the host app is in front. The extension records only the day, never a file name, a path or a count of files.
  - From the 30th counted day, without a license, the host app shows the ask when it is opened: "You've used Spacedown on {n} days", a line on how a license keeps it going, and three answers: Buy a license, I use it personally, Not now.
  - The ask lives in the host app only. It never shows in the Quick Look panel, the CLI or the MCP server.
  - It shows at most once every 90 days. It is recorded as it shows, so quitting with it open counts as a showing.
  - "I use it personally" quiets it for a year.
  - It never shows once a license is held, valid or expired.
  - The day count and the answers stay on the Mac. Spacedown sends nothing about the ask or the gate.
- **Builds from source may remove the check.** The AGPL allows it. Such a build may not use the Spacedown name or icon; [TRADEMARKS.md](../../TRADEMARKS.md) covers that.
- **Paid features: to be decided.** This ADR names no feature and no price. Each paid feature, when it comes, gets a feature code and calls the gate.

## Rationale

- **One gate, not a check per call site.** Three surfaces in two languages would drift if each read the license on its own, and a missed expiry check would unlock a feature. One answer for one code keeps the states and their wording in one place.
- **Offline and signed.** Spacedown runs offline by design ([AGENTS.md](../../AGENTS.md)). An Ed25519 signature checks offline with a small public key, and a license file can be backed up, moved and restored like any file. No account means no personal data held by Console Labs to verify a license.
- **The ask in the host app.** The Quick Look panel runs no scripts and closes on a key press: an ask there could not be answered and would get in the way of reading. The host app is where Settings and the license already belong.
- **Counting days in the panel.** People use Spacedown by pressing space in Finder and may open the app rarely. Counting only app days would never reach 30 for most users. Recording the day, and nothing else, keeps the privacy promise in [PRIVACY.md](../PRIVACY.md).
- **A failed check never sells.** A paying user whose file cannot be read is a support case, not a sale. Asking them to buy again would cost trust for nothing.
- **Polite, rare and quiet for personal use**, as TablePro's ask: the free viewer has no trial and no time limit, so the ask is a request, never a lock.

## Consequences

- No call site is gated yet. A paid feature adds its feature code, its name and one-line description for the notice, and calls the gate.
- The gate, the license file reader and the day count are new code across the app, the extension and the CLI. Where the gate sits (the render core is shared by the extension and the CLI, the app is Swift) is the implementation PR's call. A new render core hook or a new file in `load-order.txt` changes the release contract, so it goes through a contract PR first ([contract-r1.md](../contract-r1.md)).
- The CLI is a bash script that renders through `osascript`. Verifying an Ed25519 signature there needs a verifier it can run offline; which one is the implementation PR's call, and adding a runtime dependency needs a maintainer's yes.
- The extension writes the day it was used to the App Group store the app and extension already share. That store needs a Developer ID or Mac App Store signed build; an ad hoc build has no App Group, so it counts only app days. Any change to entitlements or the sandbox is a full change under [AGENTS.md](../../AGENTS.md).
- A user who never opens the host app never sees the ask. That is accepted: the ask is polite, not a gate.
- The Settings window gets a License tab for adding a license file and showing its state; `SettingsTab.shown` is where it is added.
- A purchase through the Mac App Store is not a v1 license file. If the store build sells Pro in app, that purchase feeds the same gate and gets its own ADR.
- [PRIVACY.md](../PRIVACY.md) needs a line on the day count when the code lands, in the same PR.

## Alternatives considered

- **An account and a license server in v1**, as TablePro's account. It needs a network call, personal data and a server to run, against the offline design, for no gain while every paid feature works offline.
- **A license key string checked against a server.** Same cost as an account, and a key typed by hand is easier to share than a signed file.
- **The ask in the Quick Look panel.** The panel runs no scripts, cannot open a purchase page, and is on screen for seconds.
- **The ask in the CLI or the MCP server.** A message on stderr would land in scripts and in agents' tool results, where nobody reads it as a request.
- **A time-limited trial of the viewer.** The viewer stays free with no trial or time limit; only paid features are gated.
- **A closed-source Pro build in a private repo.** Two codebases to keep in step, and contributors could not see or fix the code that runs on their Mac.

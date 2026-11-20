# r2-platform: implementation notes

Only what differs from, or adds to, the maintainer's brief for this contract PR (macOS 13 floor, universal build, `.dev` ids for Debug builds, the `Icon.png` stub, the code shield).

## Choices the brief left open

- **`.dev` ids keep the prefix rule.** An app extension's id must start with its host app's id, so `.dev` goes on the base id and the children follow: app `dfoundation.spacedown.dev`, Quick Look `dfoundation.spacedown.dev.quicklook`, Safari `dfoundation.spacedown.dev.Extension`, opener `dfoundation.spacedown.dev.opener`. The render helper's Mach service and LaunchAgent label are `dfoundation.spacedown.render.dev`, the App Group `W777S7V8TN.dfoundation.spacedown.dev`.
- **How a Debug build is made.** `build-safari.sh` takes `CONFIG=Debug` (default `Release`, so CI, `release.sh` and the size numbers are unchanged). `install.sh` takes the same variable for the opener.
- **Coexistence needs more than ids.** A Debug build installs as `Spacedown Dev.app`, shows "Spacedown Dev" and "Spacedown Dev Quick Look", and puts its helper at `~/.local/libexec/spacedown-render-dev`. Without that, two `Spacedown.app` bundles in one folder overwrite each other.
- **Entitlements stay one set of files.** For a Debug build, `build-safari.sh` signs with copies in the build folder whose App Group and Mach service name carry `.dev`, the way it already makes the release copy of the extension's entitlements.
- **A plain build still uses the release ids.** `CONFIG=Debug` is opt-in; `build-safari.sh` with no `CONFIG` installs `Spacedown.app` as before. Flipping the default is one line if the maintainer wants every local build to be `.dev`.
- **`ENABLE_DEBUG_DYLIB=NO`** on every xcodebuild call: a Debug build otherwise splits each binary into a debug dylib and a preview stub that the script's manual signing does not cover, and `codesign --verify --deep` fails.
- **The version moves here for the frozen files.** `MARKETING_VERSION` 1.2.0 in `project.yml` and the pbxproj rides this contract branch, because the agent guard refuses frozen-file edits on any other branch. The release-prep PR bumps the rest.
- **Left on the release name in a Debug build:** the Chrome native messaging host name (`dfoundation.spacedown`, not on the brief's list) and `scripts/sd-settings`, which the bundled CLI uses to read the App Group plist.

## Shield rules

- An indented code block is four or more columns of indent (a tab counts to the next multiple of four), after a blank line, a heading or the start of the document, inside the same blockquote depth. Inside a list item it needs four columns more than the item's content, so a list continuation paragraph indented four spaces still renders math.
- A code span may cross line breaks inside one paragraph. It never crosses a blank line, a fence, an indented code line, a heading, a list item marker or a table row, so a stray backtick cannot hide later math.
- Spans close on their own line first, as the old core did. Only a backtick run left open on its line pairs with the next open run of the same length on a later line. This differs from CommonMark's strict left-to-right pairing on purpose: on a 13,888-file corpus, strict pairing made three files with unfenced code gain formulas in prose, per-line-first made none.
- A multi-line span is stashed one placeholder per line, so the one-line math pass cannot pair a `$` before the span with one after it.
- For block structure, when a case is ambiguous the text is not shielded: a missed shield shows a formula where code was meant (the old behavior), an extra shield would hide real math.

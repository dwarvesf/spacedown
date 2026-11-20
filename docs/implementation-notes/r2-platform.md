# r2-platform: implementation notes

Only what differs from, or adds to, the maintainer's brief for this contract PR (macOS 13 floor, universal build, `.dev` ids for Debug builds, the `Icon.png` stub, the code shield).

## Choices the brief left open

- **`.dev` ids keep the prefix rule.** An app extension's id must start with its host app's id, so `.dev` goes on the base id and the children follow: app `dfoundation.spacedown.dev`, Quick Look `dfoundation.spacedown.dev.quicklook`, Safari `dfoundation.spacedown.dev.Extension`, opener `dfoundation.spacedown.dev.opener`. The render helper's Mach service and LaunchAgent label are `dfoundation.spacedown.render.dev`, the App Group `W777S7V8TN.dfoundation.spacedown.dev`.
- **How a Debug build is made.** `build-safari.sh` takes `CONFIG=Debug` (default `Release`, so CI, `release.sh` and the size numbers are unchanged). `install.sh` takes the same variable for the opener.
- **Coexistence needs more than ids.** A Debug build installs as `Spacedown Dev.app`, shows "Spacedown Dev" and "Spacedown Dev Quick Look", and puts its helper at `~/.local/libexec/spacedown-render-dev`. Without that, two `Spacedown.app` bundles in one folder overwrite each other.
- **Entitlements stay one set of files.** For a Debug build, `build-safari.sh` signs with copies in the build folder whose App Group and Mach service name carry `.dev`, the way it already makes the release copy of the extension's entitlements.
- **Left on the release name in a Debug build:** the Chrome native messaging host name (`dfoundation.spacedown`, not on the brief's list) and `scripts/sd-settings`, which the bundled CLI uses to read the App Group plist.

## Shield rules

- An indented code block is four or more columns of indent (a tab counts to the next multiple of four), after a blank line, a heading or the start of the document, inside the same blockquote depth. Inside a list item it needs four columns more than the item's content, so a list continuation paragraph indented four spaces still renders math.
- A code span may cross line breaks inside one paragraph. It never crosses a blank line, a fence, an indented code line, a heading, a list item marker or a table row, so a stray backtick cannot hide later math.
- When a case is ambiguous, the text is not shielded: a missed shield shows a formula where code was meant (the old behavior), an extra shield would hide real math.

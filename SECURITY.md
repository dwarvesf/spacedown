# Security policy

## Report a vulnerability

Report it privately with GitHub's private vulnerability reporting: https://github.com/consolelabs/spacedown/security/advisories/new

Do not put the details in a public issue, a pull request or a discussion. If you cannot use the form, open an issue titled "Security" with no details and a maintainer will open a private channel.

A useful report has:

- the Spacedown version (`spacedown --version` or the app's About box) and your macOS version;
- what you did, what you expected and what happened;
- a small Markdown file or command that shows the problem, if there is one.

## Supported versions

Only the latest release gets security fixes. If you run an older version, update first and check whether the problem is still there.

## What to expect

- A maintainer reads each report and replies through the advisory thread. Spacedown is a small project, so the first reply can take a few days.
- If the report is a vulnerability, we work on a fix in a private advisory branch, release it, then publish the advisory and credit you if you want that.
- If it is not a vulnerability, we say why and, where it makes sense, move it to a public issue with your agreement.
- Please give us time to ship a fix before you share the details elsewhere.

## Scope

In scope: the Quick Look extension, the host app, the `spacedown` command-line tool and its MCP server, and the render core they share.

Spacedown runs offline by design and makes no network requests. A report that shows a way to make it read files it should not read, run code from a Markdown file, or send data off the Mac is the kind we most want to hear about.

Out of scope: problems in macOS, Quick Look or a third-party tool that Spacedown only calls, and builds you modified yourself.

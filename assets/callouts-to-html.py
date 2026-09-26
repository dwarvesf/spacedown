#!/usr/bin/env python3
"""Rewrite Obsidian/GitHub callouts for spacedown's pandoc path (stdin -> stdout).

``> [!type] optional title`` plus its following ``>`` lines become a pandoc fenced
div (``::: {.sd-callout .sd-callout-<type>}``) wrapping the blockquote, with the
marker line replaced by a raw-HTML head (``<p class="sd-callout-head">``). The CSS
lives in vscode-preview-head.html and also covers the Quick Look appex's shape
(class on the blockquote itself; see quick-look/Resources/ql-render.js, the same
contract in JS). Unknown types style as note. Lines inside code fences are left
alone. Anything else passes through byte-for-byte, so the never-crash guarantee
of the render pipeline holds.
"""
import html
import re
import sys

CALLOUT_RE = re.compile(r"^ {0,3}(>[ \t]*)\[!([A-Za-z]+)\][ \t]*(.*)$")
QUOTE_RE = re.compile(r"^ {0,3}>")
FENCE_RE = re.compile(r"^ {0,3}(```|~~~)")
KNOWN = {"note", "tip", "important", "warning", "caution"}


def head_html(type_, title):
    label = type_.capitalize()
    t = ' <span class="sd-callout-title">&#183; %s</span>' % html.escape(title) if title else ""
    return '> <p class="sd-callout-head">%s%s</p>' % (label, t)


def main():
    out = sys.stdout
    in_fence = False
    in_callout = False
    for line in sys.stdin:
        line = line.rstrip("\n")
        if FENCE_RE.match(line):
            in_fence = not in_fence
        if in_callout and not QUOTE_RE.match(line):
            out.write(":::\n\n")
            in_callout = False
        m = None if in_fence else CALLOUT_RE.match(line)
        if m and not in_callout:
            type_ = m.group(2).lower()
            cls = type_ if type_ in KNOWN else "note"
            out.write("::: {.sd-callout .sd-callout-%s}\n\n" % cls)
            out.write(head_html(type_, m.group(3).strip()) + "\n")
            in_callout = True
            continue
        out.write(line + "\n")
    if in_callout:
        out.write(":::\n")


if __name__ == "__main__":
    main()

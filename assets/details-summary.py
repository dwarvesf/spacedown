#!/usr/bin/env python3
"""Keep a <details> summary on one line in spacedown's pandoc path (stdin -> stdout).

A self-check written as ``<details><summary>1. Why ...?</summary>`` reads fine on GitHub
and Obsidian, but pandoc parses the ``1.`` as the start of an ordered list. The list then
swallows the summary text, so the disclosure triangle stands alone with the question
rendered as a list below it. This pass escapes a list or heading marker that opens the
summary text (``1.``, ``2)``, ``a.``, ``-``, ``*``, ``+``, ``#``), so pandoc keeps it as
plain inline text. Lines inside code fences are left alone. Anything else passes through
byte-for-byte.
"""
import re
import sys

FENCE_RE = re.compile(r"^ {0,3}(```|~~~)")
SUMMARY_RE = re.compile(r"(<summary\b[^>]*>[ \t]*)(?:(\d{1,9}|[A-Za-z])([.)])(?=[ \t])|([-*+#]))")


def escape(match):
    if match.group(4):
        return match.group(1) + "\\" + match.group(4)
    return match.group(1) + match.group(2) + "\\" + match.group(3)


def main():
    out = []
    in_fence = False
    for line in sys.stdin.read().split("\n"):
        if FENCE_RE.match(line):
            in_fence = not in_fence
        elif not in_fence and "<summary" in line:
            line = SUMMARY_RE.sub(escape, line)
        out.append(line)
    sys.stdout.write("\n".join(out))


if __name__ == "__main__":
    main()

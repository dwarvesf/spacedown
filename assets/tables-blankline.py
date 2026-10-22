#!/usr/bin/env python3
"""Give a pipe table its own block for spacedown's pandoc path (stdin -> stdout).

GitHub, Obsidian and the Quick Look appex (marked) start a table right under a line
of text (``**Step**`` then ``| a | b |``). pandoc's markdown reader needs a blank
line first, or it folds the whole table into the paragraph as literal pipes. This
pass inserts that blank line before a table header that directly follows text.
A table with a header and no rows gets one blank row, so it renders as a fill-in table.
Lines inside code fences are left alone. Anything else passes through byte-for-byte.
"""
import re
import sys

FENCE_RE = re.compile(r"^ {0,3}(```|~~~)")
DELIM_RE = re.compile(r"^ {0,3}\|?[ \t]*:?-+:?[ \t]*(\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$")
ROW_RE = re.compile(r"^ {0,3}[^ >].*\|")


def main():
    lines = sys.stdin.read().split("\n")
    out = []
    in_fence = False
    in_table = False
    for i, line in enumerate(lines):
        if FENCE_RE.match(line):
            in_fence = not in_fence
        if not line.strip():
            in_table = False
        elif not in_fence and not in_table and ROW_RE.match(line) \
                and i + 1 < len(lines) and "|" in lines[i + 1] and DELIM_RE.match(lines[i + 1]):
            if out and out[-1].strip():
                out.append("")
            in_table = True
        out.append(line)
        if in_table and not in_fence and DELIM_RE.match(line) and "|" in line \
                and (i + 1 >= len(lines) or not ROW_RE.match(lines[i + 1])):
            cols = len([c for c in line.strip().strip("|").split("|")])
            out.append("|" + " |" * cols)
    sys.stdout.write("\n".join(out))


if __name__ == "__main__":
    main()

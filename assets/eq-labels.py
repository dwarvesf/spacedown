#!/usr/bin/env python3
"""Turn a labeled display equation into a numbered, linkable one, before pandoc runs.

memo.d.foundation writes a numbered equation on one line:

    $$ E = mc^2 $$ {#eq-energy}

Pandoc leaves "{#eq-energy}" as literal text after the formula. This pass rewrites the line to

    [$$ E = mc^2 \\tag{1} $$]{#eq-energy}

so KaTeX draws the number (1) at the right of the formula and a link to #eq-energy lands on it.
Numbers follow order of appearance, from 1. Unlabeled $$...$$ is untouched, as is anything inside
a fenced code block. A formula that already carries its own \\tag keeps it and takes no number.

Reads markdown on stdin, writes it on stdout.
"""
import re
import sys

FENCE_RE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")
EQ_RE = re.compile(r"^(\s*)\$\$(?!\$)(.+?)\$\$[ \t]*\{#([A-Za-z][A-Za-z0-9_:.-]*)\}[ \t]*$")


def main():
    fence = None
    number = 0
    out = []
    for line in sys.stdin.read().splitlines(keepends=True):
        body = line.rstrip("\r\n")
        eol = line[len(body):]
        m = FENCE_RE.match(body)
        if m:
            mark = m.group(1)
            if fence is None:
                fence = mark[0] * len(mark)
            elif mark[0] == fence[0] and len(mark) >= len(fence):
                fence = None
            out.append(line)
            continue
        eq = None if fence else EQ_RE.match(body)
        if not eq:
            out.append(line)
            continue
        indent, formula, label = eq.groups()
        formula = formula.strip()
        if "\\tag" not in formula:
            number += 1
            formula += " \\tag{%d}" % number
        out.append("%s[$$ %s $$]{#%s}%s" % (indent, formula, label, eol))
    sys.stdout.write("".join(out))


if __name__ == "__main__":
    main()

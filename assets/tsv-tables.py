#!/usr/bin/env python3
"""Pandoc JSON filter: render a ```tsv or ```csv fence as a table.

A learning Day keeps its Anki candidates as a ```tsv fence (front, tab, back) so the
lines paste straight into Anki. As a code block the rows never wrap and the backs run off
the page. This filter turns a fence whose first class is ``tsv`` or ``csv`` into an HTML
table with class ``sd-data``: no header row (the data has none), first column as the key.
Anything else, or any parse failure, passes through untouched.
"""
import csv
import html
import io
import json
import sys


def table(text, delimiter):
    rows = [r for r in csv.reader(io.StringIO(text), delimiter=delimiter) if any(c.strip() for c in r)]
    if not rows:
        return None
    width = max(len(r) for r in rows)
    rows = [r + [""] * (width - len(r)) for r in rows]
    out = ['<div class="sd-scroll"><table class="sd-data">']
    out.append("<tbody>")
    for r in rows:
        out.append("<tr>" + "".join("<td>%s</td>" % html.escape(c.strip()) for c in r) + "</tr>")
    out.append("</tbody></table></div>")
    return "".join(out)


def walk(node):
    if isinstance(node, list):
        for i, item in enumerate(node):
            if isinstance(item, dict) and item.get("t") == "CodeBlock":
                (_ident, classes, _kv), text = item["c"]
                kind = classes[0] if classes else ""
                if kind in ("tsv", "csv"):
                    rendered = table(text, "\t" if kind == "tsv" else ",")
                    if rendered:
                        node[i] = {"t": "RawBlock", "c": ["html", rendered]}
                        continue
            walk(item)
    elif isinstance(node, dict):
        for value in node.values():
            walk(value)


def main():
    raw = sys.stdin.read()
    try:
        doc = json.loads(raw)
        walk(doc["blocks"])
        sys.stdout.write(json.dumps(doc, ensure_ascii=False))
    except Exception as exc:  # never break the render over a table
        sys.stderr.write("spacedown: tsv tables skipped (%s)\n" % exc)
        sys.stdout.write(raw)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Make a rendered page self-contained for KaTeX: inline the vendored script, stylesheet and fonts.

pandoc's --math-method=katex:URL writes a <script src> and a <link rel=stylesheet> that point at
a CDN. A browser with no route to the CDN (a proxy, a VPN, an offline machine) then shows every
formula as raw TeX. This pass swaps those two tags for the copies under assets/katex/, with the
stylesheet's fonts as woff2 data: URIs (the woff and ttf fallbacks are dropped; every browser
spacedown targets reads woff2).

Usage: inline-katex.py PAGE.html   (rewrites the file in place)
Exit 0 always. A page with no KaTeX tags (no math), or vendored files that are missing, is left
as pandoc wrote it, so the CDN tags keep working as before.
"""
import base64
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KATEX = os.path.join(HERE, "katex")

SCRIPT_RE = re.compile(r'<script[^>]*\ssrc="https://[^"]*/katex\.min\.js"[^>]*></script>')
LINK_RE = re.compile(r'<link[^>]*\shref="https://[^"]*/katex\.min\.css"[^>]*/?>')
# One @font-face src list: woff2 first, then woff and truetype fallbacks.
SRC_RE = re.compile(r'url\(fonts/([^)]+\.woff2)\) format\("woff2"\)(?:,url\(fonts/[^)]+\) format\("[a-z]+"\))*')


def read(path, mode="r"):
    with open(path, mode, **({} if "b" in mode else {"encoding": "utf-8"})) as fh:
        return fh.read()


def build_css():
    def font(m):
        data = base64.b64encode(read(os.path.join(KATEX, "fonts", m.group(1)), "rb")).decode("ascii")
        return 'url(data:font/woff2;base64,%s) format("woff2")' % data

    return SRC_RE.sub(font, read(os.path.join(KATEX, "katex.min.css")))


def main():
    page = sys.argv[1]
    html = read(page)
    if not (SCRIPT_RE.search(html) and LINK_RE.search(html)):
        return
    try:
        js = read(os.path.join(KATEX, "katex.min.js"))
        css = build_css()
    except OSError as exc:
        sys.stderr.write("spacedown: katex stays on the CDN (%s)\n" % exc)
        return
    if "</script" in js:
        return
    html = SCRIPT_RE.sub(lambda m: "<script>%s</script>" % js, html, count=1)
    html = LINK_RE.sub(lambda m: "<style>%s</style>" % css, html, count=1)
    with open(page, "w", encoding="utf-8") as fh:
        fh.write(html)


if __name__ == "__main__":
    main()

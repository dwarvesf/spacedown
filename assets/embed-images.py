#!/usr/bin/env python3
"""Pandoc JSON filter: inline local images as data: URIs.

spacedown renders to a file that may be opened from another machine (the page is served
from one host and read on another), so a relative image path resolved against the source
file's directory cannot load there. This filter rewrites every LOCAL image target, a
relative or absolute path or a file: URI, into a data: URI with the right MIME type. The
page then carries its own pictures.

Skipped, left exactly as written: remote (http/https/protocol-relative) targets, existing
data: URIs, unknown extensions, files that do not exist, and files over MAX_BYTES (logged
once per file).

Contract: ``SPACEDOWN_SRC_DIR`` is the directory of the source markdown (the base for
relative paths). Without it the filter is a no-op. ``SPACEDOWN_EMBED_IMAGES=0`` turns it
off (bin/spacedown then does not register the filter at all). Reads pandoc JSON on stdin,
writes it on stdout; any failure passes the document through untouched.
"""
import base64
import json
import os
import re
import sys
import urllib.parse

MAX_BYTES = 5 * 1024 * 1024
MIME = {
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif": "image/gif",
    ".webp": "image/webp",
    ".avif": "image/avif",
}
REMOTE_RE = re.compile(r"^(?:[a-zA-Z][a-zA-Z0-9+.-]*:|//)")
HTML_IMG_SRC_RE = re.compile(r"""(<img\b[^>]*?\bsrc\s*=\s*)(["'])(.*?)\2""", re.I | re.S)

SVG_WIDTH_RE = re.compile(rb"<svg\b[^>]*?\swidth\s*=\s*[\"']([0-9.]+)(?:px)?[\"']", re.I | re.S)

src_dir = os.environ.get("SPACEDOWN_SRC_DIR", "")
cache = {}
svg_width = {}
warned = set()


def log(msg):
    sys.stderr.write("spacedown: %s\n" % msg)


def embed(target):
    """Return a data: URI for a local image target, or None to leave it alone."""
    if not target or not src_dir:
        return None
    if target in cache:
        return cache[target]
    cache[target] = None
    path = target
    if target.lower().startswith("file:"):
        path = urllib.parse.urlparse(target).path
    elif REMOTE_RE.match(target):
        return None
    path = urllib.parse.unquote(path.split("#", 1)[0].split("?", 1)[0])
    if not os.path.isabs(path):
        path = os.path.join(src_dir, path)
    ext = os.path.splitext(path)[1].lower()
    mime = MIME.get(ext)
    if not mime or not os.path.isfile(path):
        return None
    try:
        size = os.path.getsize(path)
        if size > MAX_BYTES:
            if path not in warned:
                warned.add(path)
                log("image over 5 MB, not embedded: %s (%.1f MB)" % (path, size / 1048576.0))
            return None
        with open(path, "rb") as fh:
            data = fh.read()
        payload = base64.b64encode(data).decode("ascii")
        if ext == ".svg":
            m = SVG_WIDTH_RE.search(data[:4096])
            if m:
                svg_width[target] = m.group(1).decode("ascii")
    except OSError:
        return None
    cache[target] = "data:%s;base64,%s" % (mime, payload)
    return cache[target]


def walk(node):
    if isinstance(node, list):
        for item in node:
            walk(item)
        return
    if not isinstance(node, dict):
        return
    kind = node.get("t")
    content = node.get("c")
    if kind == "Image" and isinstance(content, list) and len(content) == 3:
        target = content[2][0]
        uri = embed(target)
        if uri:
            content[2][0] = uri
            # An SVG that declares its own width keeps it, so the page does not blow it up.
            keyvals = content[0][2]
            if target in svg_width and not any(k == "width" for k, _ in keyvals):
                keyvals.append(["width", svg_width[target]])
    elif kind in ("RawInline", "RawBlock") and isinstance(content, list) and len(content) == 2:
        if str(content[0]).lower() == "html" and "<img" in content[1].lower():
            def swap(m):
                uri = embed(m.group(3))
                return "%s%s%s%s" % (m.group(1), m.group(2), uri, m.group(2)) if uri else m.group(0)
            content[1] = HTML_IMG_SRC_RE.sub(swap, content[1])
    for value in node.values():
        walk(value)


def main():
    raw = sys.stdin.read()
    try:
        doc = json.loads(raw)
        walk(doc)
        sys.stdout.write(json.dumps(doc, ensure_ascii=False))
    except Exception as exc:  # never break the render over a picture
        log("image embedding skipped (%s)" % exc)
        sys.stdout.write(raw)


if __name__ == "__main__":
    main()

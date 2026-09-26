#!/usr/bin/env python3
"""Render a leading YAML frontmatter block as an HTML properties table for md-preview.

Tolerant by design: it splits each line on the FIRST ``: `` and NEVER hands the block
to a real YAML parser, which is the exact thing that crashes pandoc on SKILL.md
``description:`` fields that contain unquoted colons (``Workflow: (1)...``). On anything
it cannot cleanly parse, it FALLS BACK to emitting the block as a ```yaml fence, so the
render never crashes. The rest of the file is passed through unchanged.

Emits ``<table class="mdp-frontmatter">`` (raw HTML; pandoc passes it through). Inline
``code`` in a value keeps its chip; everything else is HTML-escaped. Nested maps flatten
to dotted keys (depth <=2); deeper nesting or any odd shape triggers the fence fallback.
"""
import sys
import re
import html

SCALAR_RE = re.compile(r"^(true|false|null|-?\d+(?:\.\d+)?)$", re.I)
CODE_RE = re.compile(r"`([^`]+)`")
KV_RE = re.compile(r"^([^:]+):(.*)$")
# An explicit enumerated run the AUTHOR typed: " (1) ... (2) ... ". We break before the
# 2nd onward so a "Workflow: (1)... (2)... (3)..." value reads as steps, not a wall. We do
# NOT split on sentences/commas (fragile NLP); this is anchored on a deliberate token only.
ENUM_RE = re.compile(r"\s+(\(\d+\))\s")
# Values at/over this many raw chars render as a full-width stacked band (key on its own
# line, value beneath) instead of the compact 2-column row. One tunable knee.
LONG_THRESHOLD = 160


def esc(s):
    return html.escape(s, quote=False)


def soft_break_enum(html_value):
    """Break an explicit (1)... (2)... (3)... run onto separate lines (2nd marker onward).
    Gated on >=2 markers so a lone "(1)" in prose is untouched. Runs AFTER code-chip
    substitution so it never splits inside a chip."""
    if len(ENUM_RE.findall(html_value)) < 2:
        return html_value
    state = {"n": 0}

    def rep(m):
        state["n"] += 1
        if state["n"] == 1:
            return m.group(0)  # keep the first marker inline ("Workflow: (1) ...")
        return "<br>" + m.group(1) + " "

    return ENUM_RE.sub(rep, html_value)


def fmt_value(v):
    v = v.strip()
    if v == "":
        return "&nbsp;"
    # inline list: [a, b]
    if v.startswith("[") and v.endswith("]"):
        inner = v[1:-1].strip()
        items = [x.strip().strip("\"'") for x in inner.split(",")] if inner else []
        v = ", ".join(items)
        if v == "":
            return "&nbsp;"
    if SCALAR_RE.match(v):
        return '<span class="mdp-fm-scalar">%s</span>' % esc(v)
    e = esc(v)
    # turn inline `code` into a <code> chip (group already escaped), then break an
    # explicit enumerated run onto lines.
    e = CODE_RE.sub(lambda m: "<code>%s</code>" % m.group(1), e)
    return soft_break_enum(e)


def split_kv(line):
    """key, value from the FIRST ': ' (or 'key:' / 'key:value'). None if no colon."""
    m = KV_RE.match(line)
    if not m:
        return None
    key = m.group(1).strip()
    after = m.group(2)
    val = after[1:] if after.startswith(" ") else after
    return key, val


def parse_children(block, start, parent):
    """One level of indented children OR a block list under `parent`.

    Returns (rows, next_index, ok). ok=False -> caller should fall back.
    """
    n = len(block)
    i = start
    list_items = []
    child_rows = []
    saw_indent = False
    while i < n:
        line = block[i]
        if line.strip() == "":
            i += 1
            continue
        if not line[:1].isspace():
            break  # dedent back to top level
        saw_indent = True
        stripped = line.strip()
        if stripped.startswith("- "):
            list_items.append(stripped[2:].strip().strip("\"'"))
            i += 1
            continue
        kv = split_kv(stripped)
        if kv is None:
            return ([], start, False)
        ckey, cval = kv
        if cval.strip() == "":
            return ([], start, False)  # depth-3 nesting: keep it safe, fall back
        child_rows.append(("%s.%s" % (parent, ckey), fmt_value(cval),
                           len(cval.strip()) >= LONG_THRESHOLD))
        i += 1
    if not saw_indent:
        return ([], start, True)  # key had no children (plain empty value)
    if list_items and child_rows:
        return ([], start, False)  # mixed shape: fall back
    if list_items:
        joined = ", ".join(esc(x) for x in list_items) or "&nbsp;"
        return ([(parent, joined, len(joined) >= LONG_THRESHOLD)], i, True)
    return (child_rows, i, True)


def render_table(block):
    """HTML table string, or None to signal the fence fallback."""
    rows = []
    i = 0
    n = len(block)
    while i < n:
        line = block[i]
        if line.strip() == "":
            i += 1
            continue
        if line[:1].isspace():
            return None  # unexpected top-level indent
        kv = split_kv(line)
        if kv is None:
            return None  # not a key: value line (comment, stray text, ...)
        key, val = kv
        if val.strip() == "":
            child_rows, nxt, ok = parse_children(block, i + 1, key)
            if not ok:
                return None
            if child_rows:
                rows.extend(child_rows)
                i = nxt
                continue
            rows.append((key, "&nbsp;", False))
            i += 1
            continue
        rows.append((key, fmt_value(val), len(val.strip()) >= LONG_THRESHOLD))
        i += 1
    if not rows:
        return None
    # Tag the table when any value is long so CSS can widen it (more robust than :has()).
    has_long = any(is_long for _, _, is_long in rows)
    table_cls = "mdp-frontmatter mdp-fm-has-long" if has_long else "mdp-frontmatter"
    out = [
        '<table class="%s">' % table_cls,
        '<colgroup><col class="mdp-fm-col-key"><col class="mdp-fm-col-val"></colgroup>',
        "<tbody>",
    ]
    for k, v, is_long in rows:
        if is_long:
            # long value: wrap in a clamp container so CSS shows a few lines and the foot JS
            # can add a "Show more" toggle (the full text is metadata, not the main content).
            out.append(
                '<tr class="mdp-fm-row-stacked">'
                '<td class="mdp-fm-key">%s</td>'
                '<td class="mdp-fm-val mdp-fm-long"><div class="mdp-fm-clamp">%s</div></td></tr>'
                % (esc(k), v)
            )
        else:
            out.append(
                '<tr><td class="mdp-fm-key">%s</td><td class="mdp-fm-val">%s</td></tr>'
                % (esc(k), v)
            )
    out.append("</tbody></table>")
    return "\n".join(out)


def emit(s):
    sys.stdout.write(s)


def main():
    path = sys.argv[1]
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    lines = text.split("\n")

    # no leading frontmatter -> pass through unchanged
    if not lines or lines[0].rstrip("\r") != "---":
        emit(text)
        return

    close = None
    for i in range(1, len(lines)):
        s = lines[i].rstrip("\r")
        if s == "---" or s == "...":
            close = i
            break
    if close is None:
        emit(text)  # unterminated: pass through (matches the awk fallback)
        return

    block = [l.rstrip("\r") for l in lines[1:close]]
    rest = "\n".join(lines[close + 1:])

    table = None
    try:
        table = render_table(block)
    except Exception:
        table = None  # any parse surprise -> fence fallback, never crash

    if table is None:
        body = "\n".join(["```yaml"] + block + ["```"])
    else:
        body = table

    emit(body)
    emit("\n" + rest if rest else "\n")


if __name__ == "__main__":
    main()

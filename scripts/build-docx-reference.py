"""Build assets/docx/ia-reference.docx, the pandoc reference doc that gives .docx and
Google Doc exports the iA Writer look of assets/ia-theme.css.

Run after changing a style below:  python3 -I scripts/build-docx-reference.py
It starts from pandoc's own default reference doc, so every style pandoc
expects stays present, and overrides only the styles that carry the look.

Mapping from the CSS port (assets/ia-theme.css):
- one ink color for text, headings, links and rules (#1a1a1a)
- headings keep the body size; bold carries the hierarchy
- one block rhythm: every paragraph ends with the same gap
- links share the ink color, underlined
- quotes are a hairline left rule, not italics; tables use hairlines only
Fonts: iA Writer Quattro is not in Google Docs, so the body uses IBM Plex
Sans and code IBM Plex Mono (iA's fonts derive from Plex). Both are in the
Google Docs font list; Word falls back if they are not installed.
"""
import pathlib, re, subprocess, tempfile, zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "docx" / "ia-reference.docx"

INK = "1A1A1A"
SANS = "IBM Plex Sans"
MONO = "IBM Plex Mono"
BODY_HALF_PT = 24          # 12 pt
LINE = 394                 # 1.64 line height, the template's line-height-base
HEAD_LINE = 312            # 1.3 for the title and the larger headings
GAP = 300                  # 15 pt after each block, the uniform rhythm
CODE_BG = "F2F2F2"


def fonts(face):
    return f'<w:rFonts w:ascii="{face}" w:hAnsi="{face}" w:eastAsia="{face}" w:cs="{face}" />'


def run_props(face=SANS, size=BODY_HALF_PT, bold=False, extra=""):
    b = "<w:b /><w:bCs />" if bold else ""
    return (f"<w:rPr>{fonts(face)}{b}<w:color w:val=\"{INK}\" />"
            f"<w:sz w:val=\"{size}\" /><w:szCs w:val=\"{size}\" />{extra}</w:rPr>")


def para_style(sid, name, based="Normal", nxt=None, ppr="", rpr="", extra=""):
    n = f'<w:next w:val="{nxt}" />' if nxt else ""
    return (f'<w:style w:type="paragraph" w:customStyle="1" w:styleId="{sid}"><w:name w:val="{name}" />'
            f'<w:basedOn w:val="{based}" />{n}<w:qFormat />{extra}<w:pPr>{ppr}</w:pPr>{rpr}</w:style>')


def heading(level, size, before, after):
    sid = f"Heading{level}"
    line = LINE if size <= BODY_HALF_PT else HEAD_LINE
    return (f'<w:style w:type="paragraph" w:styleId="{sid}"><w:name w:val="heading {level}" />'
            f'<w:basedOn w:val="Normal" /><w:next w:val="BodyText" /><w:link w:val="{sid}Char" />'
            f'<w:uiPriority w:val="9" /><w:qFormat /><w:pPr><w:keepNext /><w:keepLines />'
            f'<w:spacing w:before="{before}" w:after="{after}" w:line="{line}" w:lineRule="auto" />'
            f'<w:outlineLvl w:val="{level - 1}" /></w:pPr>{run_props(size=size, bold=True)}</w:style>')


HAIRLINE = f'w:val="single" w:sz="4" w:space="0" w:color="{INK}"'
QUOTE_RULE = f'w:val="single" w:sz="4" w:space="12" w:color="{INK}"'

STYLES = {
    "Normal": (f'<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal" />'
               f'<w:qFormat /><w:pPr><w:spacing w:before="0" w:after="{GAP}" w:line="{LINE}" w:lineRule="auto" />'
               f'</w:pPr>{run_props()}</w:style>'),
    "BodyText": (f'<w:style w:type="paragraph" w:styleId="BodyText"><w:name w:val="Body Text" />'
                 f'<w:basedOn w:val="Normal" /><w:link w:val="BodyTextChar" /><w:qFormat />'
                 f'<w:pPr><w:spacing w:before="0" w:after="{GAP}" /></w:pPr></w:style>'),
    "Compact": para_style("Compact", "Compact", based="BodyText",
                          ppr='<w:spacing w:before="0" w:after="80" />'),
    "Title": (f'<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title" /><w:basedOn w:val="Normal" />'
              f'<w:next w:val="BodyText" /><w:link w:val="TitleChar" /><w:qFormat />'
              f'<w:pPr><w:spacing w:before="0" w:after="{GAP}" w:line="{HEAD_LINE}" w:lineRule="auto" /></w:pPr>'
              f'{run_props(size=36, bold=True)}</w:style>'),
    "Subtitle": (f'<w:style w:type="paragraph" w:styleId="Subtitle"><w:name w:val="Subtitle" />'
                 f'<w:basedOn w:val="Title" /><w:next w:val="BodyText" /><w:link w:val="SubtitleChar" /><w:qFormat />'
                 f'<w:pPr><w:spacing w:before="0" w:after="{GAP}" /></w:pPr>{run_props(size=26)}</w:style>'),
    "Heading1": heading(1, 32, 480, GAP),
    "Heading2": heading(2, 26, 480, 160),
    "Heading3": heading(3, BODY_HALF_PT, 360, 80),
    "Heading4": heading(4, BODY_HALF_PT, 240, 80),
    "BlockText": (f'<w:style w:type="paragraph" w:styleId="BlockText"><w:name w:val="Block Text" />'
                  f'<w:basedOn w:val="BodyText" /><w:next w:val="BodyText" /><w:qFormat />'
                  f'<w:pPr><w:pBdr><w:left {QUOTE_RULE} /></w:pBdr>'
                  f'<w:spacing w:before="0" w:after="{GAP}" /><w:ind w:left="240" w:right="0" w:firstLine="0" /></w:pPr>'
                  f'</w:style>'),
    "Hyperlink": (f'<w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink" />'
                  f'<w:basedOn w:val="BodyTextChar" /><w:rPr><w:color w:val="{INK}" /><w:u w:val="single" w:color="8C8C8C" />'
                  f'</w:rPr></w:style>'),
    "VerbatimChar": (f'<w:style w:type="character" w:customStyle="1" w:styleId="VerbatimChar">'
                     f'<w:name w:val="Verbatim Char" /><w:basedOn w:val="BodyTextChar" />'
                     f'<w:rPr>{fonts(MONO)}<w:sz w:val="22" /><w:shd w:val="clear" w:color="auto" w:fill="{CODE_BG}" />'
                     f'</w:rPr></w:style>'),
    "SourceCode": para_style("SourceCode", "Source Code", ppr=(
        f'<w:shd w:val="clear" w:color="auto" w:fill="{CODE_BG}" />'
        f'<w:spacing w:before="0" w:after="{GAP}" w:line="300" w:lineRule="auto" />'
        f'<w:ind w:left="120" w:right="120" />'), rpr=run_props(face=MONO, size=21)),
    "Table": (f'<w:style w:type="table" w:default="1" w:styleId="Table"><w:name w:val="Table" />'
              f'<w:basedOn w:val="TableNormal" /><w:qFormat /><w:rPr><w:sz w:val="21" /><w:szCs w:val="21" /></w:rPr>'
              f'<w:tblPr><w:tblInd w:w="0" w:type="dxa" /><w:tblBorders><w:top {HAIRLINE} /><w:bottom {HAIRLINE} />'
              f'<w:insideH {HAIRLINE} /></w:tblBorders><w:tblCellMar><w:top w:w="80" w:type="dxa" />'
              f'<w:left w:w="0" w:type="dxa" /><w:bottom w:w="80" w:type="dxa" /><w:right w:w="200" w:type="dxa" />'
              f'</w:tblCellMar></w:tblPr><w:tblStylePr w:type="firstRow"><w:rPr><w:b /></w:rPr>'
              f'<w:tcPr><w:tcBorders><w:bottom {HAIRLINE} /></w:tcBorders><w:vAlign w:val="bottom" /></w:tcPr>'
              f'</w:tblStylePr></w:style>'),
}

DOC_DEFAULTS = (f'<w:docDefaults><w:rPrDefault>{run_props()}</w:rPrDefault><w:pPrDefault><w:pPr>'
                f'<w:spacing w:after="{GAP}" w:line="{LINE}" w:lineRule="auto" /></w:pPr></w:pPrDefault></w:docDefaults>')

# US Letter, 1.5 in side margins: about 70 characters per line, the template measure.
SECT = ('<w:sectPr><w:pgSz w:w="12240" w:h="15840" /><w:pgMar w:top="1728" w:right="2160" w:bottom="1728" '
        'w:left="2160" w:header="720" w:footer="720" w:gutter="0" /></w:sectPr>')


def build():
    with tempfile.TemporaryDirectory() as tmp:
        base = pathlib.Path(tmp) / "default.docx"
        subprocess.run(["pandoc", "-o", str(base), "--print-default-data-file", "reference.docx"], check=True)
        with zipfile.ZipFile(base) as z:
            files = {n: z.read(n) for n in z.namelist()}
    styles = files["word/styles.xml"].decode()
    styles = re.sub(r"<w:docDefaults>.*?</w:docDefaults>", DOC_DEFAULTS, styles, flags=re.S)
    for sid, xml in STYLES.items():
        pat = re.compile(r'<w:style [^>]*w:styleId="%s".*?</w:style>' % sid, re.S)
        styles, n = pat.subn(lambda _m: xml, styles)
        if n == 0:
            styles = styles.replace("</w:styles>", xml + "</w:styles>")
    files["word/styles.xml"] = styles.encode()
    doc = files["word/document.xml"].decode()
    doc, n = re.subn(r"<w:sectPr[ >].*?</w:sectPr>", SECT, doc, flags=re.S)
    if n != 1:
        raise SystemExit(f"expected one sectPr in the default reference doc, found {n}")
    files["word/document.xml"] = doc.encode()
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in files.items():
            z.writestr(name, data)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    build()

//
//  MarkdownPreviewProvider.swift
//  SpacedownQL
//
//  Quick Look preview extension: spacebar a .md in Finder/Spotlight -> rendered preview.
//  Renders in-process with marked.js + KaTeX (NOT pandoc, which a sandboxed appex cannot
//  spawn) via JavaScriptCore, and reuses the spacedown CSS so it looks like the browser
//  preview. The same JS glue is node-tested in quick-look/test-render.js.
//

import Foundation
import QuickLookUI
import JavaScriptCore
import UniformTypeIdentifiers

/// Loads marked + katex + ql-render.js into one JSContext and turns markdown into HTML.
/// DOM-free (katex.renderToString), so it runs the same here as in node.
final class MarkdownRenderer {
    static let shared = MarkdownRenderer()
    private let ctx = JSContext()

    private init() {
        guard let ctx = ctx else { return }
        ctx.exceptionHandler = { _, exc in
            NSLog("SpacedownQL JS error: \(String(describing: exc))")
        }
        let bundle = Bundle(for: MarkdownRenderer.self)
        loadScript(ctx, bundle, "marked.min", "js", nil)
        loadScript(ctx, bundle, "katex.min", "js", nil)
        // Before ql-render, which reads global.hljs at parse time and degrades to
        // unhighlighted code if it is absent.
        loadScript(ctx, bundle, "highlight.min", "js", nil)
        loadScript(ctx, bundle, "ql-render", "js", nil)
    }

    private func loadScript(_ ctx: JSContext, _ b: Bundle, _ name: String, _ ext: String, _ sub: String?) {
        guard let url = b.url(forResource: name, withExtension: ext, subdirectory: sub),
              let js = try? String(contentsOf: url, encoding: .utf8) else {
            NSLog("SpacedownQL: missing resource \(sub ?? "")/\(name).\(ext)")
            return
        }
        ctx.evaluateScript(js)
    }

    /// Rendered <body> HTML for the given markdown. Falls back to escaped plain text.
    func renderBody(_ md: String) -> String {
        guard let ctx = ctx else { return "<pre>\(escape(md))</pre>" }
        ctx.setObject(md, forKeyedSubscript: "SD_SRC" as NSString)
        let result = ctx.evaluateScript("mdToHtml(SD_SRC)")
        if let html = result?.toString(), !html.isEmpty { return html }
        return "<pre>\(escape(md))</pre>"
    }

    /// Shared CSS for the page head: KaTeX stylesheet + the spacedown VS Code look.
    func headCSS() -> String {
        let b = Bundle(for: MarkdownRenderer.self)
        var head = ""
        if let k = b.url(forResource: "katex.min", withExtension: "css"),
           let css = try? String(contentsOf: k, encoding: .utf8) {
            head += "<style>\(css)</style>\n"
        }
        // md-style.html is the build-copied assets/vscode-preview-head.html (already a <style>).
        if let m = b.url(forResource: "md-style", withExtension: "html"),
           let style = try? String(contentsOf: m, encoding: .utf8) {
            head += style + "\n"
        }
        // Syntax colors, between the base look and the reading skin so the skin still
        // owns code font and size.
        if let h = b.url(forResource: "hljs-theme", withExtension: "css"),
           let css = try? String(contentsOf: h, encoding: .utf8) {
            head += "<style>\(css)</style>\n"
        }
        // Quick Look reading skin, injected last so it overrides the VS Code look:
        // serif body, larger type, a prose column. The panel cannot be zoomed and
        // is read at arm's length, so it wants book typography, not editor typography.
        // QL-only; the browser preview keeps the upstream VS Code look.
        if let r = b.url(forResource: "ql-reading", withExtension: "css"),
           let css = try? String(contentsOf: r, encoding: .utf8) {
            head += "<style>\(css)</style>\n"
        }
        return head
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private let imageMIME: [String: String] = [
    "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
    "webp": "image/webp", "svg": "image/svg+xml", "avif": "image/avif",
    "heic": "image/heic", "bmp": "image/bmp", "tiff": "image/tiff", "tif": "image/tiff",
]

/// Total bytes of image data allowed into one preview, and the per-image cap. The page
/// is built in memory and handed to Quick Look whole, so an image-heavy document must
/// not turn a spacebar tap into a 200 MB string.
private let imageBudget = 24 * 1024 * 1024
private let imageMaxSingle = 8 * 1024 * 1024

/// Rewrite local `<img src>` to `data:` URIs, resolving relative paths against the
/// document's own directory. Quick Look hands the panel raw HTML with no base URL, so a
/// relative src otherwise resolves against nothing and draws a broken placeholder. A
/// remote src is left alone and stays blocked by the page CSP, so a hostile document
/// still cannot beacon out on preview.
func inlineLocalImages(_ html: String, relativeTo docURL: URL) -> String {
    guard html.contains("<img"),
          let re = try? NSRegularExpression(pattern: "<img\\b[^>]*?\\bsrc=\"([^\"]*)\"") else { return html }
    let dir = docURL.deletingLastPathComponent()
    var out = html
    var spent = 0
    var inlined = 0
    let matches = re.matches(in: html, range: NSRange(html.startIndex..., in: html))
    // Reverse: replacing from the end keeps the earlier ranges valid.
    for m in matches.reversed() {
        guard let srcRange = Range(m.range(at: 1), in: html) else { continue }
        let raw = String(html[srcRange])
        guard !raw.isEmpty, !raw.contains("://"), !raw.hasPrefix("data:"), !raw.hasPrefix("#") else { continue }
        let path = raw.removingPercentEncoding ?? raw
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL(fileURLWithPath: path, relativeTo: dir)
        guard let mime = imageMIME[url.pathExtension.lowercased()] else { continue }
        guard let data = try? Data(contentsOf: url.standardizedFileURL) else {
            // Almost always a sandbox denial on a sibling file, which reads in the
            // panel as a broken image with no other clue. Say so in the log.
            NSLog("SpacedownQL: cannot read image %@", url.path)
            continue
        }
        guard data.count <= imageMaxSingle, spent + data.count <= imageBudget else { continue }
        spent += data.count
        let uri = "data:\(mime);base64,\(data.base64EncodedString())"
        if let r = Range(m.range(at: 1), in: out) { out.replaceSubrange(r, with: uri) }
        inlined += 1
    }
    NSLog("SpacedownQL: inlined %d/%d images, %d bytes", inlined, matches.count, spent)
    return out
}

/// Wrap rendered body + shared CSS into a self-contained HTML page.
func buildPreviewHTML(_ md: String, fileURL: URL? = nil) -> Data {
    var body = MarkdownRenderer.shared.renderBody(md)
    if let fileURL = fileURL { body = inlineLocalImages(body, relativeTo: fileURL) }
    let head = MarkdownRenderer.shared.headCSS()
    let page = """
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <!-- marked passes raw HTML through, so a hostile document can put <script> or a
         remote <img> into the panel. Styles are inline and local images arrive as
         data: URIs (inlineLocalImages), so nothing needs the network: spacebar on an
         untrusted file cannot beacon out or run anything. -->
    <meta http-equiv="Content-Security-Policy"
          content="default-src 'none'; style-src 'unsafe-inline'; img-src data:">
    <!-- Panel reset FIRST: it is the floor the stylesheets build on. Last place it
         beat ql-reading.css's centered column and outdented the whole page. -->
    <style>body { margin: 0; padding: 16px 22px; }</style>
    \(head)
    </head><body>\(body)</body></html>
    """
    return Data(page.utf8)
}

// QLPreviewingController conformance is load-bearing: Quick Look's host checks the
// principal object for it and rejects the extension without it (Apple's data-based
// sample declares both). QLIsDataBasedPreview must also be true in Info.plist.
@available(macOS 12.0, *)
class MarkdownPreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let md = (try? String(contentsOf: request.fileURL, encoding: .utf8)) ?? ""
        let data = buildPreviewHTML(md, fileURL: request.fileURL)
        NSLog("SpacedownQL: rendered %@ -> %d bytes HTML",
              request.fileURL.lastPathComponent, data.count)
        return QLPreviewReply(dataOfContentType: .html,
                              contentSize: CGSize(width: 820, height: 1040)) { _ in
            data
        }
    }
}

import AppKit

// Render a "Markdown Preview" app icon: indigo squircle, white "M↓" mark.
func icon(_ px: Int) -> Data {
    let p = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // squircle: ~10% margin, Apple-ish corner radius.
    let margin = p * 0.085
    let side = p - 2*margin
    let rect = CGRect(x: margin, y: margin, width: side, height: side)
    let radius = side * 0.2237
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // vertical indigo gradient (a touch of life vs flat fill)
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let cs = CGColorSpaceCreateDeviceRGB()
    let top = CGColor(colorSpace: cs, components: [0x63/255.0, 0x66/255.0, 0xf1/255.0, 1])!
    let bot = CGColor(colorSpace: cs, components: [0x46/255.0, 0x3a/255.0, 0xcf/255.0, 1])!
    let grad = CGGradient(colorsSpace: cs, colors: [top, bot] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: p), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    // "M↓" centered, white, heavy.
    let s = "M↓" as NSString
    let fontSize = side * 0.46
    let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .kern: -fontSize * 0.04,
    ]
    let ts = s.size(withAttributes: attrs)
    // optical centering: nudge up slightly for visual balance
    let pt = NSPoint(x: (p - ts.width)/2, y: (p - ts.height)/2 + p*0.01)
    s.draw(at: pt, withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = CommandLine.arguments[1]
for px in [16, 32, 64, 128, 256, 512, 1024] {
    let data = icon(px)
    try! data.write(to: URL(fileURLWithPath: "\(dir)/icon_\(px).png"))
    print("wrote icon_\(px).png")
}

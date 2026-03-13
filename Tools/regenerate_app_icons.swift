import AppKit
import ImageIO
import UniformTypeIdentifiers

let iconSetURL = URL(fileURLWithPath: "/Users/rabdelaal/Documents/New project/KnowBeforeYouOwe/KnowBeforeYouOwe/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

let sizeMap: [(String, Int)] = [
    ("AppIcon-20@2x.png", 40),
    ("AppIcon-20@3x.png", 60),
    ("AppIcon-29@2x.png", 58),
    ("AppIcon-29@3x.png", 87),
    ("AppIcon-40@2x.png", 80),
    ("AppIcon-40@3x.png", 120),
    ("AppIcon-60@2x.png", 120),
    ("AppIcon-60@3x.png", 180),
    ("AppIcon-20@1x~ipad.png", 20),
    ("AppIcon-20@2x~ipad.png", 40),
    ("AppIcon-29@1x~ipad.png", 29),
    ("AppIcon-29@2x~ipad.png", 58),
    ("AppIcon-40@1x~ipad.png", 40),
    ("AppIcon-40@2x~ipad.png", 80),
    ("AppIcon-76@1x.png", 76),
    ("AppIcon-76@2x.png", 152),
    ("AppIcon-83.5@2x.png", 167),
    ("AppIcon-1024@1x.png", 1024)
]

let yahooPurple = NSColor(calibratedRed: 0.38, green: 0.00, blue: 0.82, alpha: 1.0)
let electricPurple = NSColor(calibratedRed: 0.54, green: 0.29, blue: 0.98, alpha: 1.0)
let softLilac = NSColor(calibratedRed: 0.92, green: 0.89, blue: 0.99, alpha: 1.0)
let pearl = NSColor(calibratedRed: 0.98, green: 0.98, blue: 1.00, alpha: 1.0)
let mist = NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.98, alpha: 1.0)
let ink = NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.21, alpha: 1.0)
let slate = NSColor(calibratedRed: 0.43, green: 0.46, blue: 0.55, alpha: 1.0)
let mint = NSColor(calibratedRed: 0.14, green: 0.71, blue: 0.46, alpha: 1.0)

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func makeContext(size: Int) -> CGContext? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    return CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
    )
}

func drawBackground(in rect: NSRect) {
    let gradient = NSGradient(colors: [mist, softLilac, NSColor(calibratedRed: 0.88, green: 0.94, blue: 1.0, alpha: 1.0)])!
    gradient.draw(in: rect, angle: -35)

    let glow = NSBezierPath(ovalIn: NSRect(x: -90, y: rect.height * 0.56, width: rect.width * 0.78, height: rect.height * 0.5))
    NSColor(calibratedWhite: 1, alpha: 0.42).setFill()
    glow.fill()

    let bottomShape = NSBezierPath(ovalIn: NSRect(x: rect.width * 0.32, y: -160, width: rect.width * 0.9, height: rect.height * 0.46))
    yahooPurple.withAlphaComponent(0.08).setFill()
    bottomShape.fill()
}

func drawEnvelopeCard() {
    let cardRect = NSRect(x: 164, y: 214, width: 696, height: 520)
    let cardPath = roundedRect(cardRect, radius: 126)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.16)
    shadow.shadowOffset = NSSize(width: 0, height: -28)
    shadow.shadowBlurRadius = 54
    shadow.set()
    pearl.setFill()
    cardPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    let accentStripRect = NSRect(x: cardRect.minX + 82, y: cardRect.maxY - 92, width: cardRect.width - 164, height: 16)
    let accentStrip = roundedRect(accentStripRect, radius: 8)
    yahooPurple.setFill()
    accentStrip.fill()

    let flap = NSBezierPath()
    flap.lineWidth = 24
    flap.lineCapStyle = .round
    flap.move(to: NSPoint(x: cardRect.minX + 82, y: cardRect.maxY - 126))
    flap.line(to: NSPoint(x: cardRect.midX, y: cardRect.midY + 26))
    flap.line(to: NSPoint(x: cardRect.maxX - 82, y: cardRect.maxY - 126))
    NSColor(calibratedRed: 0.81, green: 0.77, blue: 0.96, alpha: 1.0).setStroke()
    flap.stroke()

    let summaryRect = NSRect(x: cardRect.minX + 96, y: cardRect.minY + 94, width: cardRect.width - 192, height: 134)
    let summaryPath = roundedRect(summaryRect, radius: 38)
    NSColor(calibratedRed: 0.97, green: 0.96, blue: 1.0, alpha: 1.0).setFill()
    summaryPath.fill()

    let countCircleRect = NSRect(x: summaryRect.minX + 34, y: summaryRect.minY + 34, width: 66, height: 66)
    let countCircle = NSBezierPath(ovalIn: countCircleRect)
    yahooPurple.withAlphaComponent(0.15).setFill()
    countCircle.fill()

    let countText = NSAttributedString(
        string: "3",
        attributes: [
            .font: NSFont.systemFont(ofSize: 36, weight: .bold),
            .foregroundColor: yahooPurple
        ]
    )
    countText.draw(at: NSPoint(x: countCircleRect.minX + 22, y: countCircleRect.minY + 14))

    let headline = NSAttributedString(
        string: "Upcoming charges",
        attributes: [
            .font: NSFont.systemFont(ofSize: 34, weight: .bold),
            .foregroundColor: ink
        ]
    )
    headline.draw(at: NSPoint(x: summaryRect.minX + 122, y: summaryRect.minY + 62))

    let detail = NSAttributedString(
        string: "One trial ends today",
        attributes: [
            .font: NSFont.systemFont(ofSize: 23, weight: .medium),
            .foregroundColor: slate
        ]
    )
    detail.draw(at: NSPoint(x: summaryRect.minX + 124, y: summaryRect.minY + 28))
}

func drawInsightLens() {
    let lensRect = NSRect(x: 328, y: 434, width: 370, height: 370)
    let outer = NSBezierPath(ovalIn: lensRect)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = yahooPurple.withAlphaComponent(0.18)
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.shadowBlurRadius = 32
    shadow.set()
    NSColor(calibratedWhite: 1, alpha: 0.98).setFill()
    outer.fill()
    NSGraphicsContext.restoreGraphicsState()

    outer.lineWidth = 18
    yahooPurple.setStroke()
    outer.stroke()

    let handle = NSBezierPath()
    handle.lineWidth = 26
    handle.lineCapStyle = .round
    handle.move(to: NSPoint(x: lensRect.maxX - 30, y: lensRect.minY + 28))
    handle.line(to: NSPoint(x: lensRect.maxX + 76, y: lensRect.minY - 72))
    yahooPurple.setStroke()
    handle.stroke()

    let dollar = NSAttributedString(
        string: "$",
        attributes: [
            .font: NSFont.systemFont(ofSize: 176, weight: .black),
            .foregroundColor: ink
        ]
    )
    dollar.draw(at: NSPoint(x: lensRect.minX + 128, y: lensRect.minY + 92))

    let greenDotRect = NSRect(x: lensRect.maxX - 82, y: lensRect.maxY - 68, width: 52, height: 52)
    let greenDot = NSBezierPath(ovalIn: greenDotRect)
    mint.setFill()
    greenDot.fill()

    let check = NSBezierPath()
    check.lineWidth = 10
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    check.move(to: NSPoint(x: greenDotRect.minX + 14, y: greenDotRect.midY - 2))
    check.line(to: NSPoint(x: greenDotRect.midX - 2, y: greenDotRect.minY + 15))
    check.line(to: NSPoint(x: greenDotRect.maxX - 12, y: greenDotRect.maxY - 14))
    NSColor.white.setStroke()
    check.stroke()
}

func drawSpark() {
    let spark = NSBezierPath()
    spark.move(to: NSPoint(x: 228, y: 792))
    spark.line(to: NSPoint(x: 246, y: 742))
    spark.line(to: NSPoint(x: 296, y: 724))
    spark.line(to: NSPoint(x: 248, y: 706))
    spark.line(to: NSPoint(x: 228, y: 656))
    spark.line(to: NSPoint(x: 210, y: 706))
    spark.line(to: NSPoint(x: 160, y: 724))
    spark.line(to: NSPoint(x: 210, y: 742))
    spark.close()
    electricPurple.setFill()
    spark.fill()
}

func renderImage(size: Int, draw: (_ rect: NSRect) -> Void) -> CGImage? {
    guard let context = makeContext(size: size) else { return nil }

    context.interpolationQuality = .high
    let rect = NSRect(x: 0, y: 0, width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    draw(rect)
    NSGraphicsContext.restoreGraphicsState()

    return context.makeImage()
}

func pngData(from cgImage: CGImage) -> Data? {
    let mutableData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        mutableData,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        return nil
    }

    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return mutableData as Data
}

guard let masterImage = renderImage(size: 1024, draw: { rect in
    drawBackground(in: rect)
    drawEnvelopeCard()
    drawInsightLens()
    drawSpark()
}) else {
    fputs("Unable to create master app icon\n", stderr)
    exit(1)
}

for (filename, size) in sizeMap {
    guard let rendered = renderImage(size: size, draw: { rect in
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.draw(masterImage, in: rect)
    }) else {
        fputs("Unable to render \(filename)\n", stderr)
        exit(1)
    }

    guard let data = pngData(from: rendered) else {
        fputs("Unable to render \(filename)\n", stderr)
        exit(1)
    }

    do {
        try data.write(to: iconSetURL.appendingPathComponent(filename), options: .atomic)
    } catch {
        fputs("Unable to write \(filename): \(error)\n", stderr)
        exit(1)
    }
}

print("Generated app icon set at \(iconSetURL.path)")

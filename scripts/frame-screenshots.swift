#!/usr/bin/env swift
// Turns the raw captures from scripts/export-screenshots.sh into App Store screenshots: the icon's
// gradient, a headline and subheadline per scene, and the capture inside a device frame drawn here.
//
//   swift scripts/frame-screenshots.swift [--locales en-US,es-ES,de-DE,fr-FR] [--raw-locale en-US] [--only <prefix>]
//
// In:   fastlane/screenshots_raw/<locale>/<prefix>-<NN-scene>.png   (iphone-69, ipad-13, duo-outer, duo-inner, watch)
//       fastlane/screenshots_mac_raw/<locale>/<NN-scene>.png          (window captures, scaled onto the 2880x1800 canvas)
//       fastlane/screenshot_captions/<locale>.json                    {"01-codes": {"title", "subtitle", "style"}}
// Out:  fastlane/screenshots/<locale>/…  and  fastlane/screenshots_mac/<locale>/…  (what fastlane deliver reads;
//       it picks the display type by pixel size, so every canvas size below is exact)
//
// A locale without raws of its own is framed from --raw-locale's, so captions can be translated before the UI.
// Captions are looked up as "<prefix>:<scene>" first ("mac:01-codes", "watch:02-detail"), then "<scene>".
// --only takes a prefix: iphone-69, ipad-13, duo-outer, duo-inner, watch or mac.
// No third-party code and no downloaded assets: everything is drawn with AppKit and Core Graphics.
import AppKit
import CoreGraphics

// MARK: - Configuration

/// Apple Watch Ultra class. Change it here when App Store Connect asks for another watch size.
let watchCanvas = CGSize(width: 422, height: 514)

let captionsDirectory = "fastlane/screenshot_captions"
let iosRaw = "fastlane/screenshots_raw"
let macRaw = "fastlane/screenshots_mac_raw"
let iosOut = "fastlane/screenshots"
let macOut = "fastlane/screenshots_mac"

enum DeviceFrame { case phone, tablet, foldable, mac, watch }

struct Kind {
    let prefix: String
    let canvas: CGSize
    let frame: DeviceFrame
    /// Headline point size as a fraction of the canvas width, before any shrinking to fit.
    let headline: CGFloat
    /// Widest the text may run, as a fraction of the canvas width.
    let textWidth: CGFloat
    /// Space above the headline, as a fraction of the canvas height.
    let top: CGFloat
    /// Space between the text and the device, as a fraction of the canvas height.
    let gap: CGFloat
    /// Widest the device may be, as a fraction of the canvas width.
    let deviceWidth: CGFloat
    /// Share of the device's height allowed to run off the bottom edge (0: the whole device shows).
    let bleed: CGFloat
    /// Space below the device when it doesn't bleed, as a fraction of the canvas height.
    let bottom: CGFloat
}

let kinds: [Kind] = [
    Kind(prefix: "iphone-69", canvas: CGSize(width: 1320, height: 2868), frame: .phone,
         headline: 0.072, textWidth: 0.86, top: 0.058, gap: 0.036, deviceWidth: 0.84, bleed: 0.045, bottom: 0),
    Kind(prefix: "ipad-13", canvas: CGSize(width: 2064, height: 2752), frame: .tablet,
         headline: 0.060, textWidth: 0.80, top: 0.055, gap: 0.038, deviceWidth: 0.86, bleed: 0.12, bottom: 0),
    Kind(prefix: "duo-outer", canvas: CGSize(width: 1398, height: 2034), frame: .foldable,
         headline: 0.070, textWidth: 0.86, top: 0.055, gap: 0.034, deviceWidth: 0.84, bleed: 0.045, bottom: 0),
    Kind(prefix: "duo-inner", canvas: CGSize(width: 2007, height: 2853), frame: .foldable,
         headline: 0.062, textWidth: 0.82, top: 0.055, gap: 0.036, deviceWidth: 0.86, bleed: 0.04, bottom: 0),
    Kind(prefix: "watch", canvas: watchCanvas, frame: .watch,
         headline: 0.078, textWidth: 0.92, top: 0.045, gap: 0.035, deviceWidth: 0.78, bleed: 0, bottom: 0.05),
    // Landscape: 6.5% of 2880 would be a 187 pt headline, so the Mac's is sized to its height instead.
    Kind(prefix: "mac", canvas: CGSize(width: 2880, height: 1800), frame: .mac,
         headline: 0.040, textWidth: 0.72, top: 0.05, gap: 0.035, deviceWidth: 0.86, bleed: 0, bottom: 0.05),
]

// MARK: - Arguments

var locales = ["en-US", "es-ES", "de-DE", "fr-FR"]
var rawLocale = "en-US"
var only: String?
var arguments = Array(CommandLine.arguments.dropFirst())
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}
while !arguments.isEmpty {
    let flag = arguments.removeFirst()
    guard let value = arguments.first, !value.hasPrefix("--") else { fail("\(flag) needs a value") }
    arguments.removeFirst()
    switch flag {
    case "--locales": locales = value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    case "--raw-locale": rawLocale = value
    case "--only":
        guard kinds.contains(where: { $0.prefix == value }) else {
            fail("--only takes one of \(kinds.map(\.prefix).joined(separator: ", "))")
        }
        only = value
    default: fail("unknown option \(flag)")
    }
}

// MARK: - Colours and styles

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

struct Style {
    let top: CGColor, bottom: CGColor
    let ring: CGColor          // ripples
    let ringOpacity: CGFloat
    let glow: CGColor          // soft light behind the device
}

let styles: [String: Style] = [
    "light": Style(top: color(0x4F8CFF), bottom: color(0x0F299C), ring: color(0xFFFFFF), ringOpacity: 0.13, glow: color(0xFFFFFF, 0.16)),
    "dark": Style(top: color(0x081A42), bottom: color(0x050D24), ring: color(0x339EFF), ringOpacity: 0.30, glow: color(0x339EFF, 0.30)),
]

// MARK: - Captions

struct Caption: Decodable { let title: String; let subtitle: String; let style: String? }

func loadCaptions(_ locale: String) -> [String: Caption] {
    let path = "\(captionsDirectory)/\(locale).json"
    guard let data = FileManager.default.contents(atPath: path) else { fail("no captions for \(locale): \(path) is missing") }
    do { return try JSONDecoder().decode([String: Caption].self, from: data) } catch { fail("\(path): \(error)") }
}

func caption(_ captions: [String: Caption], locale: String, prefix: String, scene: String) -> Caption {
    let keys = ["\(prefix):\(scene)", scene]
    guard let found = keys.lazy.compactMap({ captions[$0] }).first else {
        fail("\(captionsDirectory)/\(locale).json has no caption for \(prefix)-\(scene) (tried \(keys.map { "\"\($0)\"" }.joined(separator: ", ")))")
    }
    guard styles[found.style ?? "light"] != nil else {
        fail("\(captionsDirectory)/\(locale).json: style \"\(found.style ?? "")\" for \(scene) must be light or dark")
    }
    return found
}

// MARK: - Text

/// Lays out `string` in a box `width` wide: how many lines it takes and how tall they are.
final class TextBlock {
    let storage: NSTextStorage
    let layout = NSLayoutManager()
    let container: NSTextContainer

    init(_ string: NSAttributedString, width: CGFloat) {
        storage = NSTextStorage(attributedString: string)
        container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
    }

    var lines: Int {
        var count = 0
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, _, _, _, _ in count += 1 }
        return count
    }
    var height: CGFloat { ceil(layout.usedRect(for: container).height) }
    /// Every word fits on a line of its own: nothing was broken mid-word.
    var wordsFit: Bool {
        let words = storage.string.split(whereSeparator: \.isWhitespace)
        return words.allSatisfy { word in
            let measured = NSAttributedString(string: String(word), attributes: storage.attributes(at: 0, effectiveRange: nil))
            return measured.size().width <= container.size.width
        }
    }

    /// Draws with the top-left corner at `origin`, in a flipped (top-down) context.
    func draw(at origin: CGPoint) {
        layout.drawGlyphs(forGlyphRange: layout.glyphRange(for: container), at: origin)
    }

    /// The narrowest box that keeps the same number of lines, so two-line text breaks evenly.
    /// With `wrapLong`, a single line wider than 70% of the box becomes two even ones, so the
    /// subheadlines in a set share one shape.
    static func balanced(_ string: NSAttributedString, maxWidth: CGFloat, wrapLong: Bool = false) -> TextBlock {
        var maxWidth = maxWidth
        let single = TextBlock(string, width: maxWidth)
        let used = single.layout.usedRect(for: single.container).width
        if wrapLong, single.lines == 1, used > maxWidth * 0.7, string.string.split(separator: " ").count >= 4 {
            maxWidth = used * 0.62
        }
        let lines = TextBlock(string, width: maxWidth).lines
        guard lines > 1 else { return TextBlock(string, width: maxWidth) }
        var low = maxWidth * 0.4, high = maxWidth
        for _ in 0..<16 {
            let mid = (low + high) / 2
            if TextBlock(string, width: mid).lines <= lines { high = mid } else { low = mid }
        }
        return TextBlock(string, width: ceil(high) + 1)
    }
}

func attributed(_ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, lineHeight: CGFloat) -> NSAttributedString {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineHeightMultiple = lineHeight
    style.lineBreakMode = .byWordWrapping
    return NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor.white.withAlphaComponent(alpha),
        .paragraphStyle: style,
    ])
}

struct TextLayout {
    let title: TextBlock
    let subtitle: TextBlock
    let spacing: CGFloat
    var height: CGFloat { title.height + spacing + subtitle.height }
}

func textLayout(_ caption: Caption, kind: Kind, size: CGFloat) -> TextLayout {
    let width = kind.canvas.width * kind.textWidth
    let title = TextBlock.balanced(attributed(caption.title, size: size, weight: .bold, alpha: 1, lineHeight: 0.94), maxWidth: width)
    let subtitle = TextBlock.balanced(attributed(caption.subtitle, size: size * 0.55, weight: .medium, alpha: 0.8, lineHeight: 1.0),
                                      maxWidth: width, wrapLong: kind.canvas.height > kind.canvas.width)
    return TextLayout(title: title, subtitle: subtitle, spacing: size * 0.32)
}

/// The largest headline size, down from the kind's, at which both lines of text fit in two lines each.
func fittingSize(_ caption: Caption, kind: Kind, file: String) -> CGFloat {
    let base = kind.canvas.width * kind.headline
    var size = base
    while size >= base * 0.7 {
        let text = textLayout(caption, kind: kind, size: size)
        if text.title.lines <= 2, text.subtitle.lines <= 2, text.title.wordsFit, text.subtitle.wordsFit { return size }
        size *= 0.97
    }
    fail("the caption for \(file) doesn't fit in two lines even at 70% size: shorten \"\(caption.title)\" / \"\(caption.subtitle)\"")
}

// MARK: - Drawing helpers (top-down coordinates: the context is flipped once in render())

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    let r = min(radius, rect.width / 2, rect.height / 2)
    return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

func drawBackground(_ context: CGContext, size: CGSize, style: Style) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [style.top, style.bottom] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width * 0.25, y: size.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func drawGlow(_ context: CGContext, center: CGPoint, radius: CGFloat, style: Style) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [style.glow, style.glow.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

/// Concentric countdown rings fading outwards: the icon's ring, spreading across the image.
func drawRipples(_ context: CGContext, center: CGPoint, first: CGFloat, step: CGFloat, count: Int, width: CGFloat, style: Style) {
    context.saveGState()
    context.setLineWidth(width)
    for index in 0..<count {
        let opacity = style.ringOpacity * (1 - CGFloat(index) / CGFloat(count))
        context.setStrokeColor(style.ring.copy(alpha: opacity)!)
        context.addArc(center: center, radius: first + CGFloat(index) * step, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        context.strokePath()
    }
    context.restoreGState()
}

/// Draws an image the right way up inside `rect`, in the flipped context.
func drawImage(_ context: CGContext, _ image: CGImage, in rect: CGRect) {
    context.saveGState()
    context.interpolationQuality = .high
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: 1, y: -1)
    context.draw(image, in: CGRect(origin: .zero, size: rect.size))
    context.restoreGState()
}

// MARK: - Device frames

struct FrameMetrics {
    /// Bezel thickness and corner radii as fractions of the screen's width.
    let bezel: CGFloat
    let screenRadius: CGFloat
}

func metrics(_ frame: DeviceFrame) -> FrameMetrics {
    switch frame {
    case .phone: FrameMetrics(bezel: 0.034, screenRadius: 0.128)      // iPhone 17 Pro Max: ~55 pt display corners
    case .tablet: FrameMetrics(bezel: 0.040, screenRadius: 0.026)     // iPad Pro: thin, uniform
    case .foldable: FrameMetrics(bezel: 0.034, screenRadius: 0.085)
    case .watch: FrameMetrics(bezel: 0.075, screenRadius: 0.21)
    case .mac: FrameMetrics(bezel: 0, screenRadius: 0)                // the window brings its own chrome
    }
}

/// Side buttons: (left side?, top as a fraction of the device height, length as a fraction of it, thickness as a fraction of the screen width)
func buttons(_ frame: DeviceFrame) -> [(left: Bool, top: CGFloat, length: CGFloat, thickness: CGFloat)] {
    switch frame {
    case .phone: [(true, 0.175, 0.045, 0.009), (true, 0.245, 0.075, 0.009), (true, 0.335, 0.075, 0.009), (false, 0.27, 0.115, 0.009)]
    case .foldable: [(false, 0.20, 0.10, 0.009), (true, 0.20, 0.07, 0.009)]
    case .tablet: [(false, 0.035, 0.05, 0.005)]
    default: []
    }
}

/// Draws the capture inside its device. `outer` is the device's whole rect, `screen` the capture's.
func drawDevice(_ context: CGContext, kind: Kind, image: CGImage, outer: CGRect, screen: CGRect, macRadius: CGFloat) {
    let m = metrics(kind.frame)
    let sw = screen.width
    let edge = color(0x3A3B3F), edgeDark = color(0x1C1C1F)

    if kind.frame == .mac {
        let shape = roundedRect(screen, macRadius)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -sw * 0.012), blur: sw * 0.05, color: color(0x000A2A, 0.5))
        context.addPath(shape)
        context.setFillColor(color(0xFFFFFF))
        context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(shape)
        context.clip()
        drawImage(context, image, in: screen)
        context.restoreGState()
        // A hairline, as macOS draws around windows
        context.addPath(roundedRect(screen.insetBy(dx: 0.75, dy: 0.75), macRadius))
        context.setStrokeColor(color(0x000000, 0.18))
        context.setLineWidth(1.5)
        context.strokePath()
        return
    }

    let outerRadius = sw * (m.screenRadius + m.bezel)
    let body = roundedRect(outer, outerRadius)

    // Buttons first, so the body covers their inner half
    for button in buttons(kind.frame) {
        let thickness = sw * button.thickness
        let rect = CGRect(x: button.left ? outer.minX - thickness : outer.maxX - thickness * 0.2,
                          y: outer.minY + outer.height * button.top, width: thickness * 1.2, height: outer.height * button.length)
        context.addPath(roundedRect(rect, thickness * 0.5))
        context.setFillColor(edge)
        context.fillPath()
    }
    if kind.frame == .watch {
        // Digital Crown and side button
        let crown = CGRect(x: outer.maxX - sw * 0.02, y: outer.minY + outer.height * 0.27, width: sw * 0.075, height: outer.height * 0.2)
        context.addPath(roundedRect(crown, sw * 0.02))
        context.setFillColor(color(0x55565B))
        context.fillPath()
        context.setStrokeColor(color(0x2A2B2F))
        context.setLineWidth(max(1, sw * 0.004))
        var y = crown.minY + crown.height * 0.18
        while y < crown.maxY - crown.height * 0.12 {
            context.move(to: CGPoint(x: crown.minX + sw * 0.03, y: y))
            context.addLine(to: CGPoint(x: crown.maxX - sw * 0.008, y: y))
            y += crown.height / 9
        }
        context.strokePath()
        let side = CGRect(x: outer.maxX - sw * 0.02, y: outer.minY + outer.height * 0.6, width: sw * 0.04, height: outer.height * 0.2)
        context.addPath(roundedRect(side, sw * 0.015))
        context.setFillColor(edge)
        context.fillPath()
    }

    // Body with a soft shadow
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -sw * 0.025), blur: sw * 0.09, color: color(0x000A2A, 0.45))
    context.addPath(body)
    context.setFillColor(edgeDark)
    context.fillPath()
    context.restoreGState()

    // Metal edge: a band lighter at the top, like light from above
    context.saveGState()
    context.addPath(body)
    context.clip()
    let metal = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [color(0x6A6C72), edge, edgeDark, color(0x45474C)] as CFArray, locations: [0, 0.25, 0.75, 1])!
    context.drawLinearGradient(metal, start: CGPoint(x: outer.minX, y: outer.minY), end: CGPoint(x: outer.maxX, y: outer.maxY), options: [])
    context.restoreGState()

    // Bezel inside the edge
    let rim = sw * (kind.frame == .tablet ? 0.006 : 0.009)
    context.addPath(roundedRect(outer.insetBy(dx: rim, dy: rim), outerRadius - rim))
    context.setFillColor(color(0x111111))
    context.fillPath()

    // Thin highlight on the outer edge
    context.addPath(roundedRect(outer.insetBy(dx: sw * 0.0015, dy: sw * 0.0015), outerRadius))
    context.setStrokeColor(color(0xFFFFFF, 0.22))
    context.setLineWidth(max(1, sw * 0.002))
    context.strokePath()

    // The capture, clipped to the display's corners
    context.saveGState()
    context.addPath(roundedRect(screen, sw * m.screenRadius))
    context.clip()
    drawImage(context, image, in: screen)
    context.restoreGState()

    switch kind.frame {
    case .phone:
        // Dynamic Island: clear of the status bar the capture already shows (9:41 left, icons right)
        let island = CGRect(x: screen.midX - sw * 0.143, y: screen.minY + sw * 0.026, width: sw * 0.286, height: sw * 0.083)
        context.addPath(roundedRect(island, island.height / 2))
        context.setFillColor(color(0x000000))
        context.fillPath()
    case .tablet:
        // Front camera, on the long edge as on current iPad Pro (the right side when held upright)
        let r = sw * 0.006
        context.addEllipse(in: CGRect(x: (outer.maxX + screen.maxX) / 2 - r, y: screen.midY - r, width: 2 * r, height: 2 * r))
        context.setFillColor(color(0x24262B))
        context.fillPath()
    default: break
    }
}

/// macOS 27 window corners in a 2x capture, for when the capture can't tell (a white window's corners
/// were flattened to white too).
let defaultWindowRadius: CGFloat = 38

/// The corner radius of a window capture whose transparent corners were flattened to a solid colour:
/// walk the diagonal in from the corner until the window starts.
func windowCornerRadius(_ image: CGImage) -> CGFloat {
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let corner = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB) else { return defaultWindowRadius }
    for d in 1..<min(24, image.width, image.height) {
        guard let c = bitmap.colorAt(x: d, y: d)?.usingColorSpace(.sRGB) else { break }
        let delta = max(abs(c.redComponent - corner.redComponent), abs(c.greenComponent - corner.greenComponent), abs(c.blueComponent - corner.blueComponent))
        if delta > 0.06 { return CGFloat(d) / (1 - 1 / 2.0.squareRoot()) }
    }
    return defaultWindowRadius
}

// MARK: - Rendering

func loadImage(_ path: String) -> CGImage {
    guard let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fail("can't read \(path)") }
    return image
}

/// `textArea` is the height kept for text across the whole set, so every device sits at the same height
/// and shorter text is centred in it.
func render(kind: Kind, raw: String, caption: Caption, headline: CGFloat, textArea: CGFloat, to output: String) {
    let image = loadImage(raw)
    let size = kind.canvas
    let W = size.width, H = size.height
    if kind.frame != .mac, (image.width > image.height) != (W > H) {
        fail("\(raw) is \(image.width)x\(image.height), but \(kind.prefix) screenshots are \(Int(W))x\(Int(H)): wrong orientation")
    }
    let style = styles[caption.style ?? "light"]!

    // No alpha: App Store Connect refuses images with transparency.
    guard let context = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fail("can't create a \(Int(W))x\(Int(H)) canvas")
    }
    context.translateBy(x: 0, y: H)
    context.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

    // Text block at the top
    let text = textLayout(caption, kind: kind, size: headline)
    let textTop = (H * kind.top + (textArea - text.height) / 2).rounded()
    let deviceTop = H * kind.top + textArea + H * kind.gap

    // Device: as large as the space below the text allows (plus the bleed), capped in width
    let m = metrics(kind.frame)
    let screenAspect = CGFloat(image.height) / CGFloat(image.width)
    // outer = screen + 2 bezels; both in terms of the screen width
    let outerWidthPerScreen = 1 + 2 * m.bezel
    let outerHeightPerScreen = screenAspect + 2 * m.bezel
    let allowedHeight = kind.bleed > 0 ? (H - deviceTop) / (1 - kind.bleed) : H - deviceTop - H * kind.bottom
    var screenWidth = min(allowedHeight / outerHeightPerScreen, W * kind.deviceWidth / outerWidthPerScreen)
    screenWidth = screenWidth.rounded()
    let outerSize = CGSize(width: screenWidth * outerWidthPerScreen, height: screenWidth * outerHeightPerScreen)
    var outerTop = deviceTop
    if kind.bleed == 0 {
        // Share any spare room so the device sits centred between the text and the bottom margin
        outerTop += max(0, (allowedHeight - outerSize.height) / 2)
    }
    let outer = CGRect(x: ((W - outerSize.width) / 2).rounded(), y: outerTop.rounded(), width: outerSize.width.rounded(), height: outerSize.height.rounded())
    let bezel = screenWidth * m.bezel
    let screen = CGRect(x: outer.minX + bezel, y: outer.minY + bezel, width: screenWidth, height: (screenWidth * screenAspect).rounded())

    drawBackground(context, size: size, style: style)
    drawGlow(context, center: CGPoint(x: W / 2, y: outer.minY + outer.height * 0.2), radius: max(W, H) * 0.6, style: style)
    drawRipples(context, center: CGPoint(x: W / 2, y: outer.minY + outer.height * 0.38),
                first: max(outer.width, outer.height * 0.6) * 0.62, step: min(W, H) * 0.14, count: 7,
                width: max(1.5, min(W, H) * 0.0035), style: style)
    drawDevice(context, kind: kind, image: image, outer: outer, screen: screen, macRadius: windowCornerRadius(image) * screen.width / CGFloat(image.width))

    // Text last, so nothing covers it
    text.title.draw(at: CGPoint(x: ((W - text.title.container.size.width) / 2).rounded(), y: textTop))
    text.subtitle.draw(at: CGPoint(x: ((W - text.subtitle.container.size.width) / 2).rounded(), y: textTop + text.title.height + text.spacing))

    NSGraphicsContext.current = nil
    guard let result = context.makeImage(), result.width == Int(W), result.height == Int(H) else { fail("\(output): rendering failed") }
    let bitmap = NSBitmapImageRep(cgImage: result)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fail("\(output): PNG encoding failed") }
    do { try png.write(to: URL(filePath: output)) } catch { fail("\(output): \(error.localizedDescription)") }

    // Check what was written, not what was meant to be
    guard let written = NSBitmapImageRep(data: png), written.pixelsWide == Int(W), written.pixelsHigh == Int(H) else {
        fail("\(output) came out at the wrong size, expected \(Int(W))x\(Int(H))")
    }
    if written.hasAlpha { fail("\(output) has an alpha channel; App Store Connect rejects transparency") }
    print(String(format: "   %-40@ %dx%d", output as NSString, written.pixelsWide, written.pixelsHigh))
}

// MARK: - Main

let files = FileManager.default
func pngs(in directory: String) -> [String] {
    ((try? files.contentsOfDirectory(atPath: directory)) ?? []).filter { $0.hasSuffix(".png") }.sorted()
}

/// The locale's raws if it has any, else the --raw-locale ones.
func rawDirectory(_ root: String, locale: String) -> String? {
    let own = "\(root)/\(locale)"
    if !pngs(in: own).isEmpty { return own }
    let fallback = "\(root)/\(rawLocale)"
    return pngs(in: fallback).isEmpty ? nil : fallback
}

struct Job { let kind: Kind; let raw: String; let output: String; let caption: Caption; let file: String }

var produced = 0
for locale in locales {
    print("==> \(locale)")
    let captions = loadCaptions(locale)
    var jobs: [Job] = []

    // iOS and watch: <prefix>-<NN-scene>.png
    let iosKinds = kinds.filter { $0.frame != .mac && (only == nil || only == $0.prefix) }
    if !iosKinds.isEmpty, let raws = rawDirectory(iosRaw, locale: locale) {
        if !raws.hasSuffix("/\(locale)") { print("   (no \(locale) raws yet: framing \(raws))") }
        let out = "\(iosOut)/\(locale)"
        try? files.createDirectory(atPath: out, withIntermediateDirectories: true)
        for kind in iosKinds {
            let names = pngs(in: raws).filter { $0.hasPrefix(kind.prefix + "-") }
            guard !names.isEmpty else { continue }
            // Nothing stale may stay behind for deliver to upload
            for old in pngs(in: out) where old.hasPrefix(kind.prefix + "-") { try? files.removeItem(atPath: "\(out)/\(old)") }
            for name in names {
                let scene = String(name.dropFirst(kind.prefix.count + 1).dropLast(4))
                jobs.append(Job(kind: kind, raw: "\(raws)/\(name)", output: "\(out)/\(name)",
                                caption: caption(captions, locale: locale, prefix: kind.prefix, scene: scene), file: name))
            }
        }
    }

    // Mac: <NN-scene>.png
    if let mac = kinds.first(where: { $0.frame == .mac }), only == nil || only == mac.prefix,
       let raws = rawDirectory(macRaw, locale: locale) {
        if !raws.hasSuffix("/\(locale)") { print("   (no \(locale) Mac raws yet: framing \(raws))") }
        let out = "\(macOut)/\(locale)"
        try? files.createDirectory(atPath: out, withIntermediateDirectories: true)
        for old in pngs(in: out) { try? files.removeItem(atPath: "\(out)/\(old)") }
        for name in pngs(in: raws) {
            let scene = String(name.dropLast(4))
            jobs.append(Job(kind: mac, raw: "\(raws)/\(name)", output: "\(out)/\(name)",
                            caption: caption(captions, locale: locale, prefix: mac.prefix, scene: scene), file: "mac-\(name)"))
        }
    }

    // One headline size per device set, so the screenshots read as a series
    var sizes: [String: CGFloat] = [:]
    for job in jobs {
        let size = fittingSize(job.caption, kind: job.kind, file: "\(locale)/\(job.file)")
        sizes[job.kind.prefix] = min(sizes[job.kind.prefix] ?? .greatestFiniteMagnitude, size)
    }
    var areas: [String: CGFloat] = [:]
    for job in jobs {
        let height = textLayout(job.caption, kind: job.kind, size: sizes[job.kind.prefix]!).height
        areas[job.kind.prefix] = max(areas[job.kind.prefix] ?? 0, height)
    }
    for job in jobs {
        render(kind: job.kind, raw: job.raw, caption: job.caption, headline: sizes[job.kind.prefix]!,
               textArea: areas[job.kind.prefix]!, to: job.output)
        produced += 1
    }
    if jobs.isEmpty { print("   no raw captures found") }
}
print("\(produced) screenshot(s)")
if produced == 0 { exit(1) }

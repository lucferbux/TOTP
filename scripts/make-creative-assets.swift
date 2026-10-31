#!/usr/bin/env swift
// Draws the App Store header (3840x1646) and search results (3840x2560) images, in the icon's colours.
// The search results image shows real screenshots, so run scripts/export-screenshots.sh first.
// Usage: swift scripts/make-creative-assets.swift
import AppKit
import CoreGraphics

let screenshots = "fastlane/screenshots/en-US"
let output = URL(filePath: "fastlane/creative_assets", directoryHint: .isDirectory)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func drawBackground(_ context: CGContext, height: CGFloat) {
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0.12, 0.53, 0.96), color(0.01, 0.22, 0.58)] as CFArray, locations: [0, 1]
    )!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: .zero, options: [])
}

/// Concentric countdown rings fading outwards: the icon's ring, spreading across the image.
func drawRipples(_ context: CGContext, center: CGPoint, first: CGFloat, step: CGFloat, count: Int, width: CGFloat) {
    context.saveGState()
    context.setLineWidth(width)
    for index in 0..<count {
        let opacity = 0.16 * (1 - CGFloat(index) / CGFloat(count))
        context.setStrokeColor(color(1, 1, 1, opacity))
        context.addArc(center: center, radius: first + CGFloat(index) * step, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        context.strokePath()
    }
    context.restoreGState()
}

/// Three quarters of a turn from twelve o'clock, as on the icon.
func drawCountdown(_ context: CGContext, center: CGPoint, radius: CGFloat, width: CGFloat) {
    context.saveGState()
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setStrokeColor(color(1, 1, 1, 0.22))
    context.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    context.strokePath()
    context.setStrokeColor(color(1, 1, 1))
    context.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
    context.strokePath()
    context.restoreGState()
}

func drawText(_ text: String, font: NSFont, kern: CGFloat = 0, color textColor: NSColor, center: CGPoint, width: CGFloat) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor, .paragraphStyle: style, .kern: kern]
    let string = NSAttributedString(string: text, attributes: attributes)
    let box = string.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin])
    string.draw(with: CGRect(x: center.x - width / 2, y: center.y - box.height / 2, width: width, height: box.height), options: [.usesLineFragmentOrigin])
}

/// A screenshot with rounded corners and a soft shadow, fitted to a height and centred on `centerX`.
func drawScreenshot(_ context: CGContext, file: String, centerX: CGFloat, bottom: CGFloat, height: CGFloat, radius: CGFloat) throws {
    guard let image = NSImage(contentsOfFile: "\(screenshots)/\(file)")?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: file])
    }
    let width = height * CGFloat(image.width) / CGFloat(image.height)
    let rect = CGRect(x: centerX - width / 2, y: bottom, width: width, height: height)
    let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -24), blur: 90, color: color(0, 0.05, 0.2, 0.45))
    context.addPath(shape)
    context.setFillColor(color(1, 1, 1))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.draw(image, in: rect)
    context.restoreGState()
}

func render(_ name: String, width: Int, height: Int, draw: (CGContext) throws -> Void) throws {
    // No alpha: App Store Connect refuses images with transparency.
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    try draw(context)
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appending(path: name))
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

// One idea: a code with time left on it. The digits are made up.
try render("header-3840x1646.png", width: 3840, height: 1646) { context in
    let center = CGPoint(x: 1920, y: 860)
    drawBackground(context, height: 1646)
    drawRipples(context, center: center, first: 1150, step: 300, count: 5, width: 5)
    drawCountdown(context, center: CGPoint(x: 1150, y: center.y), radius: 150, width: 56)
    drawText("284 019", font: .monospacedDigitSystemFont(ofSize: 370, weight: .semibold), kern: 10, color: .white,
             center: CGPoint(x: 2190, y: center.y), width: 2000)
}

try render("search-results-3840x2560.png", width: 3840, height: 2560) { context in
    drawBackground(context, height: 2560)
    drawRipples(context, center: CGPoint(x: 1920, y: 1100), first: 900, step: 340, count: 6, width: 6)
    drawText("Two-factor codes, privately", font: .systemFont(ofSize: 160, weight: .bold), color: .white,
             center: CGPoint(x: 1920, y: 2330), width: 3400)
    let height: CGFloat = 2010
    try drawScreenshot(context, file: "iphone-69-03-select.png", centerX: 760, bottom: 90, height: height, radius: 130)
    try drawScreenshot(context, file: "iphone-69-01-codes.png", centerX: 1920, bottom: 90, height: height, radius: 130)
    try drawScreenshot(context, file: "iphone-69-04-add.png", centerX: 3080, bottom: 90, height: height, radius: 130)
}

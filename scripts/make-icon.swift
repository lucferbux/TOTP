#!/usr/bin/env swift
// Draws the app icon: a shield holding the countdown ring that every code runs against.
// Usage: swift scripts/make-icon.swift TOTP/Assets.xcassets/AppIcon.appiconset
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let outputDirectory = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// The shield, softened with a stroke so its points read as rounded at small sizes.
func shield() -> CGPath {
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: 512 + x, y: 512 + y) }
    let path = CGMutablePath()
    path.move(to: point(0, 320))
    path.addCurve(to: point(272, 218), control1: point(84, 268), control2: point(178, 226))
    path.addCurve(to: point(0, -330), control1: point(272, -56), control2: point(160, -244))
    path.addCurve(to: point(-272, 218), control1: point(-160, -244), control2: point(-272, -56))
    path.addCurve(to: point(0, 320), control1: point(-178, 226), control2: point(-84, 268))
    path.closeSubpath()
    return path
}

func gradient(_ context: CGContext, top: CGColor, bottom: CGColor) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [top, bottom] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: .zero, options: [])
}

func drawShield(_ context: CGContext, top: CGColor, bottom: CGColor) {
    let path = shield()
    context.saveGState()
    context.addPath(path)
    context.addPath(path.copy(strokingWithWidth: 36, lineCap: .round, lineJoin: .round, miterLimit: 1))
    context.clip()
    gradient(context, top: top, bottom: bottom)
    context.restoreGState()
}

/// Three quarters of a turn from twelve o'clock: a code with time left on it.
func drawRing(_ context: CGContext, color ringColor: CGColor) {
    context.saveGState()
    context.setStrokeColor(ringColor)
    context.setLineWidth(58)
    context.setLineCap(.round)
    context.addArc(center: CGPoint(x: 512, y: 538), radius: 124, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
    context.strokePath()
    context.restoreGState()
}

func drawLight(_ context: CGContext) {
    gradient(context, top: color(0.12, 0.53, 0.96), bottom: color(0.01, 0.22, 0.58))
    drawShield(context, top: color(1, 1, 1), bottom: color(0.93, 0.96, 1))
    drawRing(context, color: color(0.05, 0.36, 0.80))
}

func drawDark(_ context: CGContext) {
    gradient(context, top: color(0.03, 0.10, 0.26), bottom: color(0.02, 0.05, 0.14))
    drawShield(context, top: color(0.20, 0.62, 1.0), bottom: color(0.03, 0.30, 0.74))
    drawRing(context, color: color(1, 1, 1))
}

/// Tinted icons are greyscale: iOS applies the user's tint to the luminance.
func drawTinted(_ context: CGContext) {
    context.setFillColor(color(0, 0, 0))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    drawShield(context, top: color(1, 1, 1), bottom: color(0.62, 0.62, 0.62))
    drawRing(context, color: color(0, 0, 0))
}

func write(_ image: CGImage, _ name: String) throws {
    let bitmap = NSBitmapImageRep(cgImage: image)
    try bitmap.representation(using: .png, properties: [:])!.write(to: outputDirectory.appending(path: name))
}

func makeImage(pixels: Int, opaque: Bool, draw: (CGContext) -> Void) -> CGImage {
    let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: alpha.rawValue
    )!
    context.interpolationQuality = .high
    draw(context)
    return context.makeImage()!
}

/// Mac icons aren't masked for us when they're plain PNGs: a rounded rectangle on Apple's 824 pt grid.
func drawMac(_ context: CGContext, pixels: Int, artwork: CGImage) {
    let scale = CGFloat(pixels) / size
    context.scaleBy(x: scale, y: scale)
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    context.addPath(CGPath(roundedRect: plate, cornerWidth: 186, cornerHeight: 186, transform: nil))
    context.clip()
    context.draw(artwork, in: plate)
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let light = makeImage(pixels: 1024, opaque: true, draw: drawLight)
try write(light, "icon-light.png")
try write(makeImage(pixels: 1024, opaque: true, draw: drawDark), "icon-dark.png")
try write(makeImage(pixels: 1024, opaque: true, draw: drawTinted), "icon-tinted.png")

for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    try write(makeImage(pixels: pixels, opaque: false) { drawMac($0, pixels: pixels, artwork: light) }, "mac-\(pixels).png")
}

#!/usr/bin/env swift
// Draws the app icon: the countdown ring every code runs against, three quarters of the way round.
// Usage: swift scripts/make-icon.swift TOTP/Assets.xcassets/AppIcon.appiconset \
//            ["TOTP Watch/Assets.xcassets/AppIcon.appiconset"]
// The optional second directory gets the Apple Watch icon: one 1024 px universal watchOS image,
// full bleed and opaque (watchOS masks it to a circle).
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let outputDirectory = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
let watchDirectory = CommandLine.arguments.count > 2
    ? URL(filePath: CommandLine.arguments[2], directoryHint: .isDirectory)
    : nil

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func gradient(_ context: CGContext, _ colors: [CGColor], locations: [CGFloat]) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: .zero, options: [])
}

/// The countdown ring: a thick arc from twelve o'clock, clockwise, with round caps. Angles are
/// in clock terms (0 = twelve, clockwise).
func ring(sweep: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.addArc(center: CGPoint(x: 512, y: 512), radius: 300, startAngle: .pi / 2, endAngle: .pi / 2 - sweep, clockwise: true)
    return path.copy(strokingWithWidth: 132, lineCap: .round, lineJoin: .round, miterLimit: 1)
}

/// The full track, faint, then three quarters of it: a code with time left on it.
func drawRing(_ context: CGContext, track: CGColor, arc: CGColor) {
    context.addPath(ring(sweep: 2 * .pi))
    context.setFillColor(track)
    context.fillPath()
    context.addPath(ring(sweep: .pi * 1.5))
    context.setFillColor(arc)
    context.fillPath()
}

func drawLight(_ context: CGContext) {
    gradient(context, [color(0.31, 0.55, 1.0), color(0.15, 0.34, 0.91), color(0.06, 0.16, 0.61)], locations: [0, 0.5, 1])
    drawRing(context, track: color(1, 1, 1, 0.18), arc: color(1, 1, 1))
}

func drawDark(_ context: CGContext) {
    gradient(context, [color(0.06, 0.10, 0.26), color(0.02, 0.04, 0.12)], locations: [0, 1])
    drawRing(context, track: color(0.31, 0.55, 1.0, 0.18), arc: color(0.36, 0.60, 1.0))
}

/// Tinted icons are greyscale: iOS applies the user's tint to the luminance.
func drawTinted(_ context: CGContext) {
    context.setFillColor(color(0, 0, 0))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    drawRing(context, track: color(1, 1, 1, 0.22), arc: color(1, 1, 1))
}

func write(_ image: CGImage, _ name: String, in directory: URL = outputDirectory) throws {
    let bitmap = NSBitmapImageRep(cgImage: image)
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appending(path: name))
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

if let watchDirectory {
    try FileManager.default.createDirectory(at: watchDirectory, withIntermediateDirectories: true)
    try write(light, "watch-1024.png", in: watchDirectory)
    let contents = """
    {
      "images" : [
        {
          "filename" : "watch-1024.png",
          "idiom" : "universal",
          "platform" : "watchos",
          "size" : "1024x1024"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """
    try contents.write(to: watchDirectory.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
}

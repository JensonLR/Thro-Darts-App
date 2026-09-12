#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// The Apple TV's artwork, generated from the one mark the phone already carries.
//
// **tvOS wants a layered icon, and there is no way to make a good one by cropping a square.** The home
// screen icon is 5:3 and parallaxes: the layers separate as the remote moves over it, so the subject has to
// be on its own layer with the field behind. So the mark is lifted off the phone's icon by keying its own
// green out — alpha from luminance, which keeps every antialiased edge — and laid over a field drawn the
// way the board is: brand green with a lamp above it. One source of truth for the mark; the rest is
// arithmetic.
//
//     swift tools/make_tv_artwork.swift
//
// Deterministic, so re-running it produces the same bytes and a diff means somebody changed the mark.

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("apps/ios/ThroDarts/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let brand = root.appendingPathComponent("apps/ios/ThroTV/Assets.xcassets/App Icon & Top Shelf Image.brandassets")

let green = (r: 0x0F / 255.0, g: 0x3D / 255.0, b: 0x2E / 255.0)
let chalk = (r: 0xF7 / 255.0, g: 0xF6 / 255.0, b: 0xF2 / 255.0)
func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
let chalkLuma = luminance(chalk.r, chalk.g, chalk.b)

/// The mark alone, on transparency.
///
/// The phone's icon is exactly two colours, so a pixel's luminance says how much of it is chalk. Taking
/// alpha from that rather than from a threshold is what keeps the curve of the Ø smooth instead of stepped.
func markOnTransparency() -> CGImage {
    guard let data = try? Data(contentsOf: source),
          let rep = NSBitmapImageRep(data: data) else { fatalError("cannot read \(source.path)") }
    let w = rep.pixelsWide, h = rep.pixelsHigh
    // **The background is read off the image, not taken from the token.** The phone's icon was exported
    // with a green a shade lighter than `throGreen`, so keying against the token left every background
    // pixel at 6% alpha — a pale square behind the mark, uniform and therefore invisible in the source and
    // obvious the moment it was laid on a darker field. A corner pixel is the background by construction.
    guard let corner = rep.colorAt(x: 2, y: 2)?.usingColorSpace(.sRGB) else { fatalError("cannot sample") }
    let backLuma = luminance(Double(corner.redComponent), Double(corner.greenComponent), Double(corner.blueComponent))
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    for y in 0..<h {
        for x in 0..<w {
            guard let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            let lum = luminance(Double(colour.redComponent), Double(colour.greenComponent), Double(colour.blueComponent))
            let a = max(0, min(1, (lum - backLuma) / (chalkLuma - backLuma)))
            // **Premultiplied**, because that is what the context is. Writing straight chalk beside a
            // zero alpha produced a pixel whose colour is brighter than its coverage allows, which
            // CoreGraphics clamps — and the mark came out as an opaque white rectangle.
            let i = (y * w + x) * 4
            pixels[i] = UInt8((chalk.r * a * 255).rounded()); pixels[i + 1] = UInt8((chalk.g * a * 255).rounded())
            pixels[i + 2] = UInt8((chalk.b * a * 255).rounded()); pixels[i + 3] = UInt8((a * 255).rounded())
        }
    }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context.makeImage()!
}
let mark = markOnTransparency()

/// A bitmap of exactly these pixels.
///
/// **Not `NSImage.lockFocus`.** That draws at the screen's backing scale, so on a Retina Mac every "1x"
/// image came out at twice the pixels and `actool` refused the stack: *"the last image stack layer must
/// exactly fill the image stack"*, with a frame twice the size it asked for. A generator whose output
/// depends on which Mac ran it is not a generator.
func write(_ pixels: CGSize, to url: URL, draw: (CGContext) -> Void) {
    let w = Int(pixels.width), h = Int(pixels.height)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("cannot make a \(w)x\(h) context")
    }
    context.interpolationQuality = .high
    draw(context)
    guard let image = context.makeImage() else { fatalError("cannot render") }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: w, height: h)
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("cannot encode") }
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! png.write(to: url)
}

/// The field: brand green with the lamp above it, which is how every board in this app is lit.
func field(_ context: CGContext, _ size: CGSize) {
    context.setFillColor(CGColor(srgbRed: green.r, green: green.g, blue: green.b, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let lamp = CGGradient(colorsSpace: space,
                          colors: [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10),
                                   CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
                          locations: [0, 1])!
    // CoreGraphics' origin is bottom-left, so the lamp's centre sits high on the image at 0.78.
    let centre = CGPoint(x: size.width / 2, y: size.height * 0.78)
    context.drawRadialGradient(lamp, startCenter: centre, startRadius: 0,
                               endCenter: centre, endRadius: size.width * 0.62, options: [])
}

/// The mark, alone, at `height` fraction of the canvas.
func markLayer(_ context: CGContext, _ size: CGSize, height: CGFloat) {
    let side = size.height * height
    context.draw(mark, in: CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2,
                                  width: side, height: side))
}

func layer(_ stack: String, _ name: String, _ sizes: [(CGFloat, CGSize)], draw: @escaping (CGContext, CGSize) -> Void) {
    for (scale, size) in sizes {
        let suffix = scale == 1 ? "" : "@\(Int(scale))x"
        write(size, to: brand.appendingPathComponent("\(stack)/\(name).imagestacklayer/Content.imageset/layer\(suffix).png")) {
            draw($0, size)
        }
    }
}

// The home-screen icon, 400x240 at 1x. The mark at 0.60 of the height leaves the margin tvOS crops into
// when the icon is focused and grows.
let iconSizes: [(CGFloat, CGSize)] = [(1, CGSize(width: 400, height: 240)), (2, CGSize(width: 800, height: 480))]
layer("App Icon.imagestack", "Back", iconSizes) { field($0, $1) }
layer("App Icon.imagestack", "Front", iconSizes) { markLayer($0, $1, height: 0.60) }

// The App Store icon, 1280x768, one scale.
let storeSizes: [(CGFloat, CGSize)] = [(1, CGSize(width: 1280, height: 768))]
layer("App Icon - App Store.imagestack", "Back", storeSizes) { field($0, $1) }
layer("App Icon - App Store.imagestack", "Front", storeSizes) { markLayer($0, $1, height: 0.60) }

// The top shelf: one flat image, the mark smaller because this is a banner and not an icon.
for (name, w, h) in [("Top Shelf Image", 1920.0, 720.0), ("Top Shelf Image Wide", 2320.0, 720.0)] {
    for scale in [1.0, 2.0] {
        let suffix = scale == 1 ? "" : "@2x"
        let size = CGSize(width: w * scale, height: h * scale)
        write(size, to: brand.appendingPathComponent("\(name).imageset/top\(suffix).png")) {
            field($0, size)
            markLayer($0, size, height: 0.62)
        }
    }
}
// A flattened preview of the home-screen icon, written beside the assets and ignored by the catalogue.
// The layers are correct and unlookable-at on their own: one is transparent and one is a plain field.
let preview = CGSize(width: 800, height: 480)
write(preview, to: URL(fileURLWithPath: "/tmp/thro-tv-icon-preview.png")) {
    field($0, preview)
    markLayer($0, preview, height: 0.60)
}

print("make_tv_artwork: wrote the brand assets under \(brand.lastPathComponent)")

#!/usr/bin/env swift
import AppKit
import CoreGraphics
import CoreText
import Foundation

// The brand, at the sizes other people's websites ask for.
//
// **The wordmark is the app's wordmark, by construction.** THRØ's Ø is not the typeface's Ø — it is a dart
// through a ring, and the proportions were measured off Archivo ExtraBold rather than chosen
// (`MarkGeometry.Ratios.wordmark`: ring 0.524 / 0.255 of the cap, the bar 0.065 half-width running to
// ±0.95). Drawing it here from those same numbers is the difference between the brand and something that
// looks like it. A banner made in a design tool from a screenshot would drift the first time either moved.
//
//     swift tools/make_social_artwork.swift
//
// Deterministic. Re-running it produces the same bytes, so a diff means somebody changed the brand.

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let out = root.appendingPathComponent("docs/design/brand/social")
let fonts = root.appendingPathComponent("apps/ios/ThroDarts/Fonts")

let green = CGColor(srgbRed: 0x0F / 255.0, green: 0x3D / 255.0, blue: 0x2E / 255.0, alpha: 1)
let lit = CGColor(srgbRed: 0x17 / 255.0, green: 0x4F / 255.0, blue: 0x3C / 255.0, alpha: 1)
let sunken = CGColor(srgbRed: 0x0A / 255.0, green: 0x2A / 255.0, blue: 0x20 / 255.0, alpha: 1)
let chalk = CGColor(srgbRed: 0xF7 / 255.0, green: 0xF6 / 255.0, blue: 0xF2 / 255.0, alpha: 1)

// MARK: the measured geometry, from packages/client-ios/Sources/ThroDesign/Geometry.swift

let ringOuter: CGFloat = 0.524, ringInner: CGFloat = 0.255, halfWidth: CGFloat = 0.065, tipRatio: CGFloat = 0.95
let gap: CGFloat = 0.10
let capHeightPerEm: CGFloat = 687.0 / 1000.0
let tailPerCap: CGFloat = gap + ringOuter + tipRatio * (0.5 as CGFloat).squareRoot()

func face(_ file: String, size: CGFloat) -> CTFont {
    let url = fonts.appendingPathComponent(file) as CFURL
    guard let data = CGDataProvider(url: url), let cg = CGFont(data) else { fatalError("no \(file)") }
    return CTFontCreateWithGraphicsFont(cg, size, nil, nil)
}

func width(_ text: String, _ font: CTFont, tracking: CGFloat = 0) -> CGFloat {
    let attributed = NSAttributedString(string: text, attributes: [
        .font: font, .kern: tracking,
    ])
    return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil)
}

/// Draws text with its BASELINE at `origin`. CoreText's own convention, stated because every bug in this
/// file so far has been a coordinate one.
func draw(_ text: String, _ font: CTFont, at origin: CGPoint, in context: CGContext,
          colour: CGColor = chalk, tracking: CGFloat = 0) {
    let attributed = NSAttributedString(string: text, attributes: [
        .font: font, .foregroundColor: colour, .kern: tracking,
    ])
    context.textPosition = origin
    CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
}

/// The Ø: a ring, and a dart through it at 45° whose ends run well past the ring because it is a dart and
/// not a typeface's slash. Both filled in one colour, so the join cannot show.
func mark(_ context: CGContext, centre c: CGPoint, cap C: CGFloat) {
    context.setFillColor(chalk)
    // The ring, as an annulus: two circles, filled even-odd.
    context.beginPath()
    context.addEllipse(in: CGRect(x: c.x - ringOuter * C, y: c.y - ringOuter * C,
                                  width: 2 * ringOuter * C, height: 2 * ringOuter * C))
    context.addEllipse(in: CGRect(x: c.x - ringInner * C, y: c.y - ringInner * C,
                                  width: 2 * ringInner * C, height: 2 * ringInner * C))
    context.fillPath(using: .evenOdd)

    // The bar: tip, shoulder, shoulder, tip, shoulder, shoulder — full width between the ring crossings
    // and tapering to a point beyond them. The axis runs lower-left to upper-right at 45°.
    let a = (0.5 as CGFloat).squareRoot()
    let axis = CGPoint(x: a, y: a)              // y-up here; the app's frame is y-down and mirrors it
    let across = CGPoint(x: -axis.y, y: axis.x)
    func on(_ along: CGFloat, _ side: CGFloat = 0) -> CGPoint {
        CGPoint(x: c.x + axis.x * along + across.x * side, y: c.y + axis.y * along + across.y * side)
    }
    let L = tipRatio * C, R = ringOuter * C, w = halfWidth * C
    context.beginPath()
    let pts = [on(L), on(R, w), on(-R, w), on(-L), on(-R, -w), on(R, -w)]
    context.move(to: pts[0])
    for p in pts.dropFirst() { context.addLine(to: p) }
    context.closePath()
    context.fillPath()
}

/// THRØ at a cap height, its left edge at `left` and its baseline at `baseline`. Returns the whole width.
@discardableResult
func wordmark(_ context: CGContext, cap C: CGFloat, left: CGFloat, baseline: CGFloat) -> CGFloat {
    let font = face("Archivo-ExtraBold.ttf", size: C / capHeightPerEm)
    draw("THR", font, at: CGPoint(x: left, y: baseline), in: context)
    let thr = width("THR", font)
    mark(context, centre: CGPoint(x: left + thr + (gap + ringOuter) * C, y: baseline + C / 2), cap: C)
    return thr + tailPerCap * C
}

func wordmarkWidth(cap C: CGFloat) -> CGFloat {
    width("THR", face("Archivo-ExtraBold.ttf", size: C / capHeightPerEm)) + tailPerCap * C
}

func canvas(_ w: Int, _ h: Int, _ body: (CGContext) -> Void) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("cannot make a \(w)x\(h) context") }
    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    body(context)
    return context.makeImage()!
}

/// The board: the field with the lamp above it, the same three stops as everywhere else.
func field(_ context: CGContext, _ w: CGFloat, _ h: CGFloat) {
    context.setFillColor(green)
    context.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let lamp = CGGradient(colorsSpace: space, colors: [lit, green, sunken] as CFArray,
                          locations: [0, 0.55, 1])!
    let centre = CGPoint(x: w / 2, y: h * 0.72)
    context.drawRadialGradient(lamp, startCenter: centre, startRadius: 0,
                               endCenter: centre, endRadius: max(w, h) * 0.86, options: [])
}

/// A banner: the board, the wordmark centred in the safe area, the tagline under it.
func banner(_ w: Int, _ h: Int, safeHeight: CGFloat? = nil, capFraction: CGFloat = 0.30) -> CGImage {
    canvas(w, h) { context in
        let W = CGFloat(w), H = CGFloat(h)
        field(context, W, H)
        // YouTube crops a 2560x1440 banner to 1546x423 on a phone, so the composition is sized against the
        // part that always survives rather than against the file.
        let safe = safeHeight ?? H
        let C = safe * capFraction
        let total = wordmarkWidth(cap: C)
        let baseline = H / 2 - C / 2 + safe * 0.06
        wordmark(context, cap: C, left: (W - total) / 2, baseline: baseline)

        let small = face("Archivo-Medium.ttf", size: C * 0.15)
        let line = "FROM THE PUB BOARD TO THE WORLD STAGE"
        let tracking = C * 0.15 * 0.18
        let tw = width(line, small, tracking: tracking)
        draw(line, small, at: CGPoint(x: (W - tw) / 2, y: baseline - C * 0.42), in: context,
             colour: chalk.copy(alpha: 0.72)!, tracking: tracking)
    }
}

func write(_ image: CGImage, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("cannot encode") }
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    try! png.write(to: out.appendingPathComponent(name))
    print("  \(name)  \(image.width)x\(image.height)")
}

print("make_social_artwork:")
write(banner(1500, 500), "x-header-1500x500.png")
write(banner(2560, 1440, safeHeight: 423), "youtube-banner-2560x1440.png")
write(banner(1200, 630), "open-graph-1200x630.png")
write(banner(820, 312), "facebook-cover-820x312.png")
write(banner(1128, 191, capFraction: 0.34), "linkedin-cover-1128x191.png")

#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// A grid of stills, in one image.
//
// **An animation cannot be judged one frame at a time.** THRØ's opening has been through eight versions and
// every one of them was reviewed by somebody watching it and saying what they saw; a still tells you almost
// nothing about a motion, and sixteen stills read one after another tell you only slightly more, because by
// the fourth you have forgotten the first. Side by side on one sheet, the shape of the thing is visible: what
// holds too long, what happens too fast to see, where nothing is happening at all.
//
//     swift tools/contact_sheet.swift out.png 4 <frame-1.png> <frame-2.png> …
//
// The number is how many columns. Each cell is captioned with its file's basename, so a cell that looks wrong
// says which moment it was.

let args = CommandLine.arguments
guard args.count >= 4, let columns = Int(args[2]), columns > 0 else {
    FileHandle.standardError.write(Data("usage: contact_sheet.swift <out.png> <columns> <in.png>…\n".utf8))
    exit(2)
}
let out = URL(fileURLWithPath: args[1])
let inputs = args[3...].map { URL(fileURLWithPath: $0) }

let images: [(NSImage, String)] = inputs.compactMap { url in
    guard let image = NSImage(contentsOf: url) else {
        FileHandle.standardError.write(Data("cannot read \(url.path)\n".utf8))
        return nil
    }
    return (image, url.deletingPathExtension().lastPathComponent)
}
guard let first = images.first?.0 else { exit(1) }

// Cells are sized from the first image, scaled so a sheet of any number of frames stays a sensible size.
let cellWidth: CGFloat = 380
let scale = cellWidth / first.size.width
let cellHeight = (first.size.height * scale).rounded()
let caption: CGFloat = 26
let gap: CGFloat = 8
let rows = Int((Double(images.count) / Double(columns)).rounded(.up))
let width = CGFloat(columns) * cellWidth + CGFloat(columns + 1) * gap
let height = CGFloat(rows) * (cellHeight + caption) + CGFloat(rows + 1) * gap

let sheet = NSImage(size: NSSize(width: width, height: height))
sheet.lockFocus()
NSColor.black.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

let style = NSMutableParagraphStyle()
style.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
    .foregroundColor: NSColor.white,
    .paragraphStyle: style,
]

for (index, entry) in images.enumerated() {
    let column = index % columns
    let row = index / columns
    let x = gap + CGFloat(column) * (cellWidth + gap)
    // AppKit's origin is bottom-left; the sheet reads top-left, so rows count down.
    let y = height - gap - CGFloat(row + 1) * (cellHeight + caption) - CGFloat(row) * gap
    entry.0.draw(in: NSRect(x: x, y: y + caption, width: cellWidth, height: cellHeight))
    NSString(string: entry.1).draw(in: NSRect(x: x, y: y + 4, width: cellWidth, height: caption - 6),
                                   withAttributes: attributes)
}
sheet.unlockFocus()

guard let tiff = sheet.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: out)
print("contact_sheet: \(images.count) frames, \(columns) columns → \(out.path)")

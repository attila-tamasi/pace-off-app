#!/usr/bin/env swift
// generate_icon.swift
//
// Renders the Pace Off app icon as a 1024×1024 PNG using the SF Symbol
// `figure.run` — unmodified, just tinted white — on the brand blue gradient.
// Writes the resulting PNG into all three asset catalogs (iOS app, Watch app,
// Widget). Run from the project root:
//
//     swift scripts/generate_icon.swift
//
// Output conforms to Apple's icon requirements:
//   • Exactly 1024 × 1024 px
//   • Opaque RGB (no alpha channel — Apple rejects icons with alpha)
//   • Square, full-bleed (Apple applies the squircle / circle mask)
//   • Generous breathing room around the glyph so the Watch's circular mask
//     doesn't crop it. Apple's guideline is content should sit inside the
//     center ~80% of the canvas; we run a bit tighter than that.
//
// Requires: macOS 11+ (for `NSImage(systemSymbolName:)`).

import AppKit
import Foundation

// MARK: - Tunables

let canvasSize: Int = 1024

/// Point size for the SF Symbol. Sized so the rendered glyph sits inside
/// the inscribed circle of the canvas (so the watchOS circular mask doesn't
/// clip the figure's reach).  The previous 560 pt was too big and filled
/// the corners; 420 pt leaves ~20% air on each side.
let glyphPointSize: CGFloat = 420

// MARK: - Brand gradient

let topColor    = NSColor(srgbRed:  60/255, green: 163/255, blue: 255/255, alpha: 1) // #3CA3FF
let bottomColor = NSColor(srgbRed:   5/255, green:  60/255, blue: 145/255, alpha: 1) // #053C91

// MARK: - Render

func renderIcon() -> Data {
    // Explicitly opaque RGB bitmap — `hasAlpha: false` is the single line
    // that guarantees the resulting PNG has no alpha channel, which is what
    // App Store Connect / asset validation requires for icons.
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: canvasSize,
        pixelsHigh: canvasSize,
        bitsPerSample: 8,
        samplesPerPixel: 3,
        hasAlpha: false,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Failed to create opaque bitmap representation.")
    }

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Failed to create graphics context.")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    // Background gradient — bright systemBlue → deep navy, top to bottom.
    let bgRect = NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
    NSGradient(starting: topColor, ending: bottomColor)!
        .draw(in: bgRect, angle: -90)

    // Subtle top-left sheen for a touch of depth (mirrors Apple's first-party
    // icons). Kept very low opacity so it never reads as a "spotlight".
    let sheen = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.20),
        NSColor.white.withAlphaComponent(0.0)
    ])!
    sheen.draw(in: bgRect, relativeCenterPosition: NSPoint(x: -0.3, y: 0.8))

    // SF Symbol `figure.run`, unmodified shape, just tinted white.
    guard let symbol = NSImage(systemSymbolName: "figure.run",
                                accessibilityDescription: nil) else {
        fatalError("SF Symbol `figure.run` not available on this macOS.")
    }
    let configured = symbol.withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: glyphPointSize, weight: .semibold)
    )!

    // White-tint the symbol by drawing it into a fresh canvas, then masking
    // a white fill on top using .sourceAtop.
    let tinted = NSImage(size: configured.size)
    tinted.lockFocus()
    configured.draw(at: .zero,
                    from: NSRect(origin: .zero, size: configured.size),
                    operation: .sourceOver,
                    fraction: 1.0)
    NSColor.white.set()
    NSRect(origin: .zero, size: configured.size).fill(using: .sourceAtop)
    tinted.unlockFocus()

    // Center the glyph on the canvas.
    let originX = (CGFloat(canvasSize) - tinted.size.width)  / 2
    let originY = (CGFloat(canvasSize) - tinted.size.height) / 2
    tinted.draw(at: NSPoint(x: originX, y: originY),
                from: NSRect(origin: .zero, size: tinted.size),
                operation: .sourceOver,
                fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()

    // Encode PNG — properties left empty so we keep the bitmap's `hasAlpha`
    // setting (false). NSBitmapImageRep handles the rest.
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding failed.")
    }
    return data
}

// MARK: - Install

let projectRoot = FileManager.default.currentDirectoryPath
let assetPaths = [
    "PaceOff/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png",
    "PaceOffWatch Watch App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png",
    "PaceOffWidget/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
]

let data = renderIcon()
print("Rendered icon — \(data.count) bytes, 1024×1024, opaque RGB.")

for relative in assetPaths {
    let url = URL(fileURLWithPath: projectRoot).appendingPathComponent(relative)
    do {
        try data.write(to: url, options: .atomic)
        print("  Wrote \(relative)")
    } catch {
        print("  FAILED \(relative): \(error.localizedDescription)")
    }
}

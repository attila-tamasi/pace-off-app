#!/usr/bin/env swift
// render_app_icon.swift
// One-shot AppKit renderer that produces the 1024×1024 App Store icon for
// Pace Off. Same visual DNA as SplashView / AuthGateView: warm gradient
// backdrop + figure.run hero glyph + subtle motion streaks behind it.
//
// Run:    swift scripts/render_app_icon.swift
// Output: PaceOff/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
//         (Xcode derives smaller sizes from the universal 1024 entry.)

import AppKit
import CoreGraphics

let size: CGFloat = 1024
let rect = CGRect(x: 0, y: 0, width: size, height: size)

// Palette — kept in sync with BrandPalette.swift. Hex literals below match:
//   accentColor          = systemOrange ≈ #FF9F0A
//   warm midtone         = #C7501A
//   deep warm shadow     = #6B2A0D
//   cream foreground     = #FFF4E6  (matches "warm cream" requested for the figure)
//   accent particle      = #FFE08A  (sunny yellow, used in the splash blobs too)
let topColor = NSColor(srgbRed: 1.00, green: 0.62, blue: 0.04, alpha: 1.0)
let midColor = NSColor(srgbRed: 0.78, green: 0.31, blue: 0.10, alpha: 1.0)
let botColor = NSColor(srgbRed: 0.42, green: 0.16, blue: 0.05, alpha: 1.0)
let cream    = NSColor(srgbRed: 1.00, green: 0.957, blue: 0.902, alpha: 1.0)
let sunny    = NSColor(srgbRed: 1.00, green: 0.88, blue: 0.54, alpha: 1.0)

// Render into a fixed-resolution bitmap rep so the file is always 1024×1024
// regardless of the host display's backing scale. NSImage.lockFocus would
// otherwise emit a 2x asset on retina Macs.
let pixels = Int(size)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixels,
    pixelsHigh: pixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 32
) else {
    fatalError("Could not allocate NSBitmapImageRep")
}
bitmap.size = NSSize(width: size, height: size)

let bitmapContext = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = bitmapContext
let ctx = bitmapContext.cgContext

// MARK: - 1. Vertical brand gradient backdrop

let colorSpace = CGColorSpaceCreateDeviceRGB()
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [topColor.cgColor, midColor.cgColor, botColor.cgColor] as CFArray,
    locations: [0.0, 0.55, 1.0]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: size / 2, y: size),
    end: CGPoint(x: size / 2, y: 0),
    options: []
)

// MARK: - 2. Soft drifting orbs (matches the auth-screen backdrop)

func drawOrb(center: CGPoint, radius: CGFloat, color: NSColor, alpha: CGFloat) {
    ctx.saveGState()
    let orbRect = CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    )
    let path = CGPath(ellipseIn: orbRect, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(color.withAlphaComponent(alpha).cgColor)
    ctx.setShadow(offset: .zero, blur: radius * 0.9, color: color.withAlphaComponent(alpha * 0.8).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
}

drawOrb(center: CGPoint(x: size * 0.18, y: size * 0.85), radius: 230, color: cream, alpha: 0.22)
drawOrb(center: CGPoint(x: size * 0.82, y: size * 0.22), radius: 200, color: sunny, alpha: 0.20)

// MARK: - 3. Motion streaks behind the figure

ctx.saveGState()
ctx.setBlendMode(.plusLighter)
let streakOriginX: CGFloat = size * 0.18
let streakAnchorY: CGFloat = size * 0.55
let streakSpacing: CGFloat = size * 0.045
for i in 0..<5 {
    let length = size * (0.30 - CGFloat(i) * 0.045)
    let thickness = size * (0.024 - CGFloat(i) * 0.0028)
    let y = streakAnchorY + CGFloat(i - 2) * streakSpacing
    let alpha: CGFloat = 0.18 + (0.18 * CGFloat(2 - abs(i - 2))) / 2.0

    let streakRect = CGRect(
        x: streakOriginX,
        y: y - thickness / 2,
        width: length,
        height: thickness
    )
    let pill = CGPath(
        roundedRect: streakRect,
        cornerWidth: thickness / 2,
        cornerHeight: thickness / 2,
        transform: nil
    )
    ctx.addPath(pill)
    ctx.setFillColor(cream.withAlphaComponent(alpha).cgColor)
    ctx.fillPath()
}
ctx.restoreGState()

// MARK: - 4. Tiny speed particles (small floating dots)

let particles: [(x: CGFloat, y: CGFloat, r: CGFloat, a: CGFloat)] = [
    (0.12, 0.32, 8,  0.45),
    (0.16, 0.40, 5,  0.35),
    (0.10, 0.62, 6,  0.40),
    (0.08, 0.50, 10, 0.50),
    (0.20, 0.28, 7,  0.42),
    (0.14, 0.72, 5,  0.32),
]
for p in particles {
    let cx = size * p.x
    let cy = size * p.y
    let pRect = CGRect(x: cx - p.r, y: cy - p.r, width: p.r * 2, height: p.r * 2)
    ctx.addPath(CGPath(ellipseIn: pRect, transform: nil))
    ctx.setFillColor(cream.withAlphaComponent(p.a).cgColor)
    ctx.fillPath()
}

// MARK: - 5. The figure.run hero glyph

// We use SF Symbols via NSImage on macOS. The symbol is rendered with a
// soft warm-cream glow underneath, then the cream glyph on top.
guard let runSymbol = NSImage(
    systemSymbolName: "figure.run",
    accessibilityDescription: "Runner"
) else {
    fatalError("Could not load figure.run SF Symbol — does this macOS version support it?")
}

let symbolConfig = NSImage.SymbolConfiguration(pointSize: 620, weight: .heavy)
let configured = runSymbol.withSymbolConfiguration(symbolConfig) ?? runSymbol

// Tint to cream
let tinted = NSImage(size: configured.size, flipped: false) { tintRect -> Bool in
    cream.set()
    tintRect.fill()
    configured.draw(in: tintRect, from: .zero, operation: .destinationIn, fraction: 1.0)
    return true
}

let drawSize = NSSize(width: 720, height: 720)
let drawOrigin = NSPoint(
    x: (size - drawSize.width) / 2,
    y: (size - drawSize.height) / 2 - 20  // nudge down slightly for optical centering
)
let drawRect = NSRect(origin: drawOrigin, size: drawSize)

// Soft glow shadow behind the symbol
ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: -8),
    blur: 60,
    color: NSColor(srgbRed: 1.0, green: 0.94, blue: 0.85, alpha: 0.55).cgColor
)
tinted.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
ctx.restoreGState()

// Crisp foreground pass (no shadow) so edges stay sharp at small sizes
tinted.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)

NSGraphicsContext.restoreGraphicsState()

// MARK: - 6. Save as PNG

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Failed to build PNG representation")
}

// Resolve output path relative to this script's location so the script
// works whether invoked from the repo root or anywhere else.
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let scriptsDir = scriptURL.deletingLastPathComponent()
let repoRoot = scriptsDir.deletingLastPathComponent()
let outputs: [URL] = [
    repoRoot.appendingPathComponent("PaceOff/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"),
    repoRoot.appendingPathComponent("PaceOffWidget/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"),
    repoRoot.appendingPathComponent("PaceOffWatch Watch App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"),
]

for url in outputs {
    do {
        try pngData.write(to: url, options: .atomic)
        print("✓ Wrote \(url.path)")
    } catch {
        FileHandle.standardError.write(Data("✗ Failed to write \(url.path): \(error)\n".utf8))
        exit(1)
    }
}

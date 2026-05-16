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
// Requires: macOS 11+ (for `NSImage(systemSymbolName:)`).

import AppKit
import Foundation

// MARK: - Tunables

let canvasSize: CGFloat = 1024

/// Point size for the SF Symbol. Roughly the height of the glyph in points;
/// `figure.run` renders a bit wider than tall, so 560pt comfortably fills the
/// frame without crowding the squircle mask Apple applies at runtime.
let glyphPointSize: CGFloat = 560

// MARK: - Brand gradient

let topColor    = NSColor(srgbRed:  60/255, green: 163/255, blue: 255/255, alpha: 1) // #3CA3FF
let bottomColor = NSColor(srgbRed:   5/255, green:  60/255, blue: 145/255, alpha: 1) // #053C91

// MARK: - Render

func renderIcon() -> Data {
    let size = NSSize(width: canvasSize, height: canvasSize)
    let canvas = NSImage(size: size)
    canvas.lockFocus()

    // Vertical gradient background (-90° = top → bottom in NSGradient's math).
    let gradient = NSGradient(starting: topColor, ending: bottomColor)!
    gradient.draw(in: NSRect(origin: .zero, size: size), angle: -90)

    // SF Symbol `figure.run`, unmodified, tinted white.
    guard let symbol = NSImage(systemSymbolName: "figure.run",
                                accessibilityDescription: nil) else {
        fatalError("SF Symbol `figure.run` not available on this macOS.")
    }
    let configured = symbol.withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: glyphPointSize, weight: .semibold)
    )!

    // Apply the white tint by drawing into a fresh image and masking.
    let tinted = NSImage(size: configured.size)
    tinted.lockFocus()
    configured.draw(at: .zero, from: NSRect(origin: .zero, size: configured.size),
                    operation: .sourceOver, fraction: 1.0)
    NSColor.white.set()
    NSRect(origin: .zero, size: configured.size).fill(using: .sourceAtop)
    tinted.unlockFocus()

    // Center on the canvas.
    let originX = (canvasSize - tinted.size.width)  / 2
    let originY = (canvasSize - tinted.size.height) / 2
    tinted.draw(in: NSRect(x: originX, y: originY,
                           width: tinted.size.width, height: tinted.size.height))

    canvas.unlockFocus()

    // Encode as PNG.
    guard let cgImage = canvas.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("Failed to snapshot canvas to CGImage.")
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = size
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
print("Rendered icon: \(data.count) bytes")

for relative in assetPaths {
    let url = URL(fileURLWithPath: projectRoot).appendingPathComponent(relative)
    do {
        try data.write(to: url, options: .atomic)
        print("  Wrote \(relative)")
    } catch {
        print("  FAILED \(relative): \(error.localizedDescription)")
    }
}

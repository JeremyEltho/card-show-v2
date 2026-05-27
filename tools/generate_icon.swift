#!/usr/bin/env swift

// Renders the CardShowPro app icon (1024×1024 PNG) using CoreGraphics.
// Run from the repo root:
//   swift tools/generate_icon.swift
// Output:
//   v2-ios/CardShowPro/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024
let cs = CGColorSpaceCreateDeviceRGB()

guard let ctx = CGContext(
    data: nil,
    width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("Couldn't create bitmap context") }

ctx.setShouldAntialias(true)
ctx.interpolationQuality = .high

// ──────────────────────────────────────────────────────────
// 1. Background — felt-green radial gradient (matches Theme.Colors.bg / surface)
// ──────────────────────────────────────────────────────────
let bgInner = CGColor(red: 0.11, green: 0.24, blue: 0.17, alpha: 1) // Theme.Colors.surfaceHi
let bgOuter = CGColor(red: 0.04, green: 0.08, blue: 0.05, alpha: 1) // Theme.Colors.bg
let bgGradient = CGGradient(
    colorsSpace: cs,
    colors: [bgInner, bgOuter] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawRadialGradient(
    bgGradient,
    startCenter: CGPoint(x: size * 0.5, y: size * 0.55), startRadius: 0,
    endCenter:   CGPoint(x: size * 0.5, y: size * 0.5),  endRadius: size * 0.75,
    options: []
)

// ──────────────────────────────────────────────────────────
// 2. Holo rainbow halo behind the pokeball (very subtle)
// ──────────────────────────────────────────────────────────
let haloColors: [CGColor] = [
    CGColor(red: 1.00, green: 0.10, blue: 0.55, alpha: 0.0),  // pink, transparent inside
    CGColor(red: 1.00, green: 0.65, blue: 0.10, alpha: 0.20), // orange
    CGColor(red: 0.98, green: 0.93, blue: 0.20, alpha: 0.18), // yellow
    CGColor(red: 0.20, green: 0.93, blue: 0.55, alpha: 0.18), // green
    CGColor(red: 0.15, green: 0.82, blue: 0.96, alpha: 0.15), // cyan
    CGColor(red: 0.55, green: 0.20, blue: 0.96, alpha: 0.0),  // purple, fade out
]
let haloGradient = CGGradient(colorsSpace: cs, colors: haloColors as CFArray,
                              locations: [0.0, 0.4, 0.6, 0.75, 0.9, 1.0])!
ctx.drawRadialGradient(
    haloGradient,
    startCenter: CGPoint(x: size * 0.5, y: size * 0.5), startRadius: size * 0.25,
    endCenter:   CGPoint(x: size * 0.5, y: size * 0.5), endRadius: size * 0.48,
    options: []
)

// ──────────────────────────────────────────────────────────
// 3. Pokeball — large, centered, slight tilt
// ──────────────────────────────────────────────────────────
let pokeballSize: CGFloat = size * 0.62
let centerX = size / 2
let centerY = size / 2
let pokeballRect = CGRect(
    x: centerX - pokeballSize / 2,
    y: centerY - pokeballSize / 2,
    width: pokeballSize,
    height: pokeballSize
)

// Tilt -8° around centre.
ctx.saveGState()
ctx.translateBy(x: centerX, y: centerY)
ctx.rotate(by: -8 * .pi / 180)
ctx.translateBy(x: -centerX, y: -centerY)

// Drop shadow.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 28,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))

// Outer black ring (full circle).
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.fillEllipse(in: pokeballRect)
ctx.restoreGState() // end shadow

// White inset background (slightly smaller so the black ring shows).
let ringWidth = pokeballSize * 0.06
let innerRect = pokeballRect.insetBy(dx: ringWidth, dy: ringWidth)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fillEllipse(in: innerRect)

// Red top half — clip to the inner circle, then fill the top half.
ctx.saveGState()
ctx.addEllipse(in: innerRect)
ctx.clip()
let topHalf = CGRect(
    x: innerRect.minX,
    y: centerY, // upper half in flipped coords
    width: innerRect.width,
    height: innerRect.height / 2
)
ctx.setFillColor(CGColor(red: 0.92, green: 0.18, blue: 0.20, alpha: 1))
ctx.fill(topHalf)
ctx.restoreGState()

// Black equatorial band.
let bandHeight = pokeballSize * 0.10
let bandRect = CGRect(
    x: pokeballRect.minX,
    y: centerY - bandHeight / 2,
    width: pokeballRect.width,
    height: bandHeight
)
ctx.saveGState()
ctx.addEllipse(in: innerRect)
ctx.clip()
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.fill(bandRect)
ctx.restoreGState()
// Band also overlaps the outer black ring band — fill across the whole width
// so the line reads as one continuous black stripe.
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.fill(bandRect)

// Centre button — black ring + white core.
let buttonOuterSize = pokeballSize * 0.22
let buttonOuterRect = CGRect(
    x: centerX - buttonOuterSize / 2,
    y: centerY - buttonOuterSize / 2,
    width: buttonOuterSize,
    height: buttonOuterSize
)
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.fillEllipse(in: buttonOuterRect)

let buttonInnerSize = buttonOuterSize * 0.62
let buttonInnerRect = CGRect(
    x: centerX - buttonInnerSize / 2,
    y: centerY - buttonInnerSize / 2,
    width: buttonInnerSize,
    height: buttonInnerSize
)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fillEllipse(in: buttonInnerRect)

// Subtle gloss highlight on the upper-left of the red half — adds depth.
ctx.saveGState()
ctx.addEllipse(in: innerRect)
ctx.clip()
let glossPath = CGMutablePath()
let glossRect = CGRect(
    x: innerRect.minX + innerRect.width * 0.14,
    y: innerRect.minY + innerRect.height * 0.10,
    width: innerRect.width * 0.34,
    height: innerRect.height * 0.18
)
glossPath.addEllipse(in: glossRect)
ctx.addPath(glossPath)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))
ctx.fillPath()
ctx.restoreGState()

ctx.restoreGState() // end tilt

// ──────────────────────────────────────────────────────────
// 4. Export
// ──────────────────────────────────────────────────────────
guard let cgImage = ctx.makeImage() else { fatalError("Couldn't make image") }

let outputPath = "v2-ios/CardShowPro/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
let url = URL(fileURLWithPath: outputPath)
guard let dest = CGImageDestinationCreateWithURL(
    url as CFURL,
    UTType.png.identifier as CFString,
    1, nil
) else { fatalError("Couldn't create image destination at \(outputPath)") }

CGImageDestinationAddImage(dest, cgImage, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("Couldn't write PNG") }

print("Wrote \(outputPath)")

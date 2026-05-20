#!/usr/bin/env swift
// Standalone Swift CLI to OCR an image using Apple Vision — mirrors the iOS scanner pipeline.
// Usage: swift ocr.swift /path/to/image.jpg

import Foundation
import Vision
import AppKit
import CoreImage

guard CommandLine.arguments.count >= 2 else {
    print("Usage: swift ocr.swift <image-path>")
    exit(1)
}

let path = CommandLine.arguments[1]
guard let image = NSImage(contentsOfFile: path),
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let cgImage = bitmap.cgImage else {
    print("ERROR: cannot load \(path)")
    exit(1)
}

// Multi-crop OCR: run Vision on 30% and 35% title-band crops, plus full image as fallback.
// Different crop ratios pick up text differently (the 30% crop tends to be cleaner on small
// cards like Charmander; the 35% recovers names that fall just below the 30% line on cards
// like Lugia/Dark Charizard). Merging gives both.
let ciImage = CIImage(cgImage: cgImage)
let ext = ciImage.extent
let context = CIContext()

func ocr(_ img: CGImage, languages: [String] = ["en-US", "ja"]) -> [(CGRect, String, Float)] {
    var out: [(CGRect, String, Float)] = []
    let request = VNRecognizeTextRequest { req, _ in
        guard let observations = req.results as? [VNRecognizedTextObservation] else { return }
        for obs in observations {
            if let candidate = obs.topCandidates(1).first {
                out.append((obs.boundingBox, candidate.string, candidate.confidence))
            }
        }
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = languages
    let handler = VNImageRequestHandler(cgImage: img, options: [:])
    try? handler.perform([request])
    return out
}

func cropTop(_ img: CIImage, fraction: CGFloat) -> CGImage? {
    let cropY = img.extent.maxY * (1.0 - fraction)
    let band = img.cropped(to: CGRect(
        x: img.extent.minX, y: cropY,
        width: img.extent.width, height: img.extent.maxY - cropY))
    return context.createCGImage(band, from: band.extent)
}

var allLines: [(text: String, confidence: Float, source: String)] = []
var seen = Set<String>()

func addResults(_ results: [(CGRect, String, Float)], _ source: String) {
    let sorted = results.sorted { $0.0.midY > $1.0.midY }
    for (_, text, conf) in sorted {
        let key = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty || seen.contains(key) { continue }
        seen.insert(key)
        allLines.append((text, conf, source))
    }
}

// Crop 30% (tighter title band — cleaner for small cards)
if let cg30 = cropTop(ciImage, fraction: 0.30) {
    addResults(ocr(cg30), "crop30")
}
// Crop 35% (wider — catches text positioned slightly lower)
if let cg35 = cropTop(ciImage, fraction: 0.35) {
    addResults(ocr(cg35), "crop35")
}

// NOTE: full-image fallback intentionally disabled. When the title band has no readable
// text, the full-image OCR returns rules text, attack names, and set logos — which create
// confident-but-wrong matches against the canonical name dictionary. Better to fail loudly
// (routing the user to manual entry) than auto-confirm garbage.

// Filter: drop low-confidence "full" pass lines (rules text, set logos, attack names).
// Title-band lines pass through even at low confidence — they're more likely to be the card name.
let filtered = allLines.filter { line in
    if line.source == "full" { return line.confidence >= 0.5 }
    return true
}

// Emit "TEXT|confidence|source" per line so the backend can use OCR confidence in ranking
for line in filtered {
    print("\(line.text)|\(String(format: "%.2f", line.confidence))|\(line.source)")
}
